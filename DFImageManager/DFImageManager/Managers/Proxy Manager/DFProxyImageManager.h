// The MIT License (MIT)
//
// Copyright (c) 2014 Alexander Grebenyuk (github.com/kean).
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

#import "DFImageManagerProtocol.h"
#import "DFImageManagerValueTransformerProtocol.h"
#import <Foundation/Foundation.h>


/*! Use proxy image manager in case you need to transform application specific interfaces to the interfaces supported by the image manager. Image manager will always recieve transformed assets.
 */
@interface DFProxyImageManager : NSProxy <DFImageManager>

@property (nonatomic) id<DFCoreImageManager> imageManager;

- (instancetype)initWithImageManager:(id<DFCoreImageManager>)imageManager;

/*! Set value transformer in case you need to transform assets before passing them to the image manager factory and to the image managers.
 */
@property (nonatomic) id<DFImageManagerValueTransformer> valueTransformer;

- (void)setValueTransformerWithBlock:(id (^)(id asset))valueTransfomer;

@end
