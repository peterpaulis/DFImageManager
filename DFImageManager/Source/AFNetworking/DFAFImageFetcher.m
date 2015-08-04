// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "DFAFImageDeserializer.h"
#import "DFAFImageFetcher.h"
#import "DFImageRequestOptions.h"
#import "DFImageManagerDefines.h"
#import "DFImageRequest.h"

NSString *const DFAFRequestCachePolicyKey = @"DFAFRequestCachePolicyKey";

@interface _DFAFImageFetchingOperation : NSObject<DFImageFetchingOperation>

@property (nonatomic, copy) void (^cancellationHandler)(void);
@property (nonatomic, copy) void (^priorityHandler)(DFImageRequestPriority priority);

@end

@implementation _DFAFImageFetchingOperation {
    BOOL _cancelled;
    DFImageRequestPriority _priority;
}

- (instancetype)init {
    if (self = [super init]) {
        _priority = DFImageRequestPriorityNormal;
    }
    return self;
}

- (void)cancelImageFetching {
    @synchronized(self) {
        if (!_cancelled) {
            _cancelled = YES;
            if (self.cancellationHandler) {
                self.cancellationHandler();
            }
        }
    }
}

- (void)setImageFetchingPriority:(DFImageRequestPriority)priority {
    @synchronized(self) {
        if (_priority != priority) {
            _priority = priority;
            if (self.priorityHandler) {
                self.priorityHandler(priority);
            }
        }
    }
}

@end


@interface _DFDataTaskDelegate : NSObject

@property (nonatomic, copy) void (^dataTaskDidReceiveDataBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data);

@end

@implementation _DFDataTaskDelegate

@end


@implementation DFAFImageFetcher {
    NSMutableDictionary *_dataTaskDelegates;
}

- (instancetype)initWithSessionManager:(AFURLSessionManager *)sessionManager {
    if (self = [super init]) {
        _sessionManager = sessionManager;
        _dataTaskDelegates = [NSMutableDictionary new];
        DFAFImageFetcher *__weak weakSelf = self;
        [sessionManager setDataTaskDidReceiveDataBlock:^(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
            DFAFImageFetcher *strongSelf = weakSelf;
            _DFDataTaskDelegate *delegate;
            @synchronized(strongSelf) {
                delegate = strongSelf->_dataTaskDelegates[dataTask];
            }
            if (delegate.dataTaskDidReceiveDataBlock) {
                delegate.dataTaskDidReceiveDataBlock(session, dataTask, data);
            }
        }];
        _supportedSchemes = [NSSet setWithObjects:@"http", @"https", @"ftp", @"file", @"data", nil];
    }
    return self;
}

#pragma mark <DFImageFetching>

- (BOOL)canHandleRequest:(DFImageRequest *)request {
    if ([request.resource isKindOfClass:[NSURL class]]) {
        return [self.supportedSchemes containsObject:((NSURL *)request.resource).scheme];
    }
    return NO;
}

- (BOOL)isRequestFetchEquivalent:(DFImageRequest *)request1 toRequest:(DFImageRequest *)request2 {
    if (![self isRequestCacheEquivalent:request1 toRequest:request2]) {
        return NO;
    }
    if (request1.options.allowsNetworkAccess != request2.options.allowsNetworkAccess) {
        return NO;
    }
    NSURLRequestCachePolicy defaultCachePolicy = self.sessionManager.session.configuration.requestCachePolicy;
    NSURLRequestCachePolicy cachePolicy1 = request1.options.userInfo[DFAFRequestCachePolicyKey] ? [request1.options.userInfo[DFAFRequestCachePolicyKey] unsignedIntegerValue] : defaultCachePolicy;
    NSURLRequestCachePolicy cachePolicy2 = request2.options.userInfo[DFAFRequestCachePolicyKey] ? [request2.options.userInfo[DFAFRequestCachePolicyKey] unsignedIntegerValue] : defaultCachePolicy;
    return cachePolicy1 == cachePolicy2;
}

- (BOOL)isRequestCacheEquivalent:(DFImageRequest *)request1 toRequest:(DFImageRequest *)request2 {
    return request1 == request2 || [(NSURL *)request1.resource isEqual:(NSURL *)request2.resource];
}

- (nonnull id<DFImageFetchingOperation>)startOperationWithRequest:(nonnull DFImageRequest *)request progressHandler:(nullable DFImageFetchingProgressHandler)progressHandler completion:(nullable DFImageFetchingCompletionHandler)completion {
    NSURLRequest *URLRequest = [self _URLRequestForImageRequest:request];
    DFAFImageFetcher *__weak weakSelf = self;
    NSURLSessionDataTask *__block task = [self.sessionManager dataTaskWithRequest:URLRequest completionHandler:^(NSURLResponse *URLResponse, UIImage *result, NSError *error) {
        DFAFImageFetcher *strongSelf = weakSelf;
        @synchronized(strongSelf) {
            [strongSelf->_dataTaskDelegates removeObjectForKey:task];
        }
        if (completion) {
            completion(result, nil, error);
        }
    }];
    [task resume];
    
    // Track progress using dataTaskDidReceiveDataBlock exposed by AFURLSessionManager.
    _DFDataTaskDelegate *dataTaskDelegate = [_DFDataTaskDelegate new];
    [dataTaskDelegate setDataTaskDidReceiveDataBlock:^(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
        if (progressHandler) {
            progressHandler(dataTask.countOfBytesReceived, dataTask.countOfBytesExpectedToReceive);
        }
    }];
    @synchronized(self) {
        _dataTaskDelegates[task] = dataTaskDelegate;
    }
    
    _DFAFImageFetchingOperation *operation = [_DFAFImageFetchingOperation new];
    operation.cancellationHandler = ^{
        [task cancel];
    };
    operation.priorityHandler = ^(DFImageRequestPriority priority){
        if ([task respondsToSelector:@selector(setPriority:)]) {
            task.priority = [DFAFImageFetcher _taskPriorityForImageRequestPriority:priority];
        }
    };
    return operation;
}

#pragma mark Support

- (NSURLRequest *)_URLRequestForImageRequest:(DFImageRequest *)imageRequest {
    NSURLRequest *URLRequest = [self _defaultURLRequestForImageRequest:imageRequest];
    if ([self.delegate respondsToSelector:@selector(imageFetcher:URLRequestForImageRequest:URLRequest:)]) {
        URLRequest = [self.delegate imageFetcher:self URLRequestForImageRequest:imageRequest URLRequest:URLRequest];
    }
    return URLRequest;
}

- (NSURLRequest *)_defaultURLRequestForImageRequest:(DFImageRequest *)imageRequest {
    NSMutableURLRequest *URLRequest = [[NSMutableURLRequest alloc] initWithURL:(NSURL *)imageRequest.resource];
#ifdef DF_IMAGE_MANAGER_WEBP_AVAILABLE
    [URLRequest addValue:@"image/webp,image/*;q=0.8" forHTTPHeaderField:@"Accept"];
#else
    [URLRequest addValue:@"image/*" forHTTPHeaderField:@"Accept"];
#endif
    DFImageRequestOptions *options = imageRequest.options;
    if (options.userInfo[DFAFRequestCachePolicyKey]) {
        URLRequest.cachePolicy = [options.userInfo[DFAFRequestCachePolicyKey] unsignedIntegerValue];
    } else {
        URLRequest.cachePolicy = options.allowsNetworkAccess ? self.sessionManager.session.configuration.requestCachePolicy : NSURLRequestReturnCacheDataDontLoad;
    }
    return [URLRequest copy];
}

+ (float)_taskPriorityForImageRequestPriority:(DFImageRequestPriority)queuePriority {
    switch (queuePriority) {
        case DFImageRequestPriorityVeryHigh: return 0.9f;
        case DFImageRequestPriorityHigh: return 0.7f;
        case DFImageRequestPriorityNormal: return 0.5f;
        case DFImageRequestPriorityLow: return 0.3f;
        case DFImageRequestPriorityVeryLow: return 0.1f;
    }
}

@end
