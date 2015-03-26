/*
 Copyright (c) 2015 Mats Mattsson

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
 rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
 WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Foundation/Foundation.h>

#import "MMNibArchive.h"

@interface MMNibArchiveValue : NSObject <NSCopying>

@property (nonatomic, readonly) NSUInteger keyIndex;
@property (nonatomic, readonly) enum MMNibArchiveValueType type;
@property (nonatomic, readonly, strong) NSData *data;

- (instancetype)initWithData:(NSData *)data ofType:(enum MMNibArchiveValueType)type forKeyIndex:(NSUInteger)keyIndex;

- (instancetype)initWithObjectReference:(uint32_t)objectReference forKeyIndex:(NSUInteger)keyIndex;
@property (nonatomic, readonly) uint32_t objectReference;


- (instancetype)initWithDataValue:(NSData *)dataValue forKeyIndex:(NSUInteger)keyIndex;
@property (nonatomic, readonly, strong) NSData *dataValue;

- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@end
