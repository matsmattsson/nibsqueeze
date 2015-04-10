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

#import "MMNibArchiveTypes.h"
#import "MMNibArchiveClassName.h"
#import "MMNibArchiveObject.h"
#import "MMNibArchiveValue.h"


extern NSString * const MMNibArchiveErrorDomain;

extern BOOL MMNibArchiveReadVarLengthInteger(const uint8_t * const bytes, const size_t numberOfBytes, size_t *offsetPtr, size_t *resultPtr);
extern size_t MMNibArchiveSerializedLengthForInteger(size_t value);
extern BOOL MMNibArchiveWriteVarLengthInteger(uint8_t * const bytes, const size_t numberOfBytes, size_t *offsetPtr, size_t value);

@interface MMNibArchive : NSObject

/**
 The full NIBArchive file data.
 */
@property (nonatomic, strong, readonly) NSData *data;

/**
 The key array used to decode objects. Contains NSData objects.
 */
@property (nonatomic, strong, readonly) NSArray *keys;

/**
 The value array used to decode objects. Contains MMNibArchiveValue objects.
 */
@property (nonatomic, strong, readonly) NSArray *values;

/**
 The class name array used to decode objects. Contains MMNibArchiveClassName objects.
 */
@property (nonatomic, strong, readonly) NSArray *classNames;

/**
 The object array used to decode objects. Contains MMNibArchiveObject objects.
 */
@property (nonatomic, strong, readonly) NSArray *objects;

- (instancetype)init;
- (instancetype)initWithData:(NSData *)data error:(NSError **)errorPtr;
- (instancetype)initWithObjects:(NSArray *)objects keys:(NSArray *)keys values:(NSArray *)values classNames:(NSArray *)classNames error:(NSError **)errorPtr;

@end
