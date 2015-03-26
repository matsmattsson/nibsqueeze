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

#import "MMNibArchiveValue.h"

#import "MMMacros.h"

@implementation MMNibArchiveValue {
	BOOL m_hasCalculatedHash;
	NSUInteger m_hash;
}
@synthesize keyIndex = m_keyIndex;
@synthesize type = m_type;
@synthesize data = m_data;

- (void)dealloc {
	MM_release(m_data);
	MM_super_dealloc;
}

- (instancetype)initWithData:(NSData *)data ofType:(enum MMNibArchiveValueType)type forKeyIndex:(NSUInteger)keyIndex {
	self = [super init];
	if (self) {
		m_keyIndex = keyIndex;
		m_type = type;
		m_data = [data copy];
	}
	return self;
}

- (instancetype)initWithObjectReference:(uint32_t)objectReference forKeyIndex:(NSUInteger)keyIndex {
	enum MMNibArchiveValueType type = kMMNibArchiveValueTypeObjectReference;
	uint32_t v = CFSwapInt32HostToLittle(objectReference);
	NSData *data = [NSData dataWithBytes:&v length:sizeof(v)];
	return [self initWithData:data ofType:type forKeyIndex:keyIndex];
}

- (uint32_t)objectReference {
	uint32_t v = 0;
	if ( sizeof(v) <= [m_data length]) {
		memcpy(&v, [m_data bytes], sizeof(v));
	}
	return CFSwapInt32LittleToHost(v);
}

- (instancetype)initWithDataValue:(NSData *)dataValue forKeyIndex:(NSUInteger)keyIndex {
	enum MMNibArchiveValueType type = kMMNibArchiveValueTypeData;
	NSUInteger const dataValueLength = [dataValue length];
	size_t const lengthSize = MMNibArchiveSerializedLengthForInteger(dataValueLength);
	NSUInteger const dataLength = NSUIntegerMax - lengthSize >= dataValueLength ? lengthSize + dataValueLength : 0;
	NSMutableData *mutableData = 0 < dataLength ? [NSMutableData dataWithLength:dataLength] : nil;
	NSData *data = nil;
	if (mutableData) {
		uint8_t * const bytes = [mutableData mutableBytes];
		size_t offset = 0;
		if (MMNibArchiveWriteVarLengthInteger(bytes, dataLength, &offset, dataValueLength)) {
			if (offset == lengthSize) {
				memcpy(bytes + offset, [dataValue bytes], dataValueLength);
				data = [mutableData copy];
				MM_autorelease(data);
			}
		}
	}

	if (data) {
		self = [self initWithData:data ofType:type forKeyIndex:keyIndex];
	} else {
		MM_release(self);
		self = nil;
	}
	return self;
}

- (NSData *)dataValue {
	NSData *dataValue = nil;
	if (m_type == kMMNibArchiveValueTypeData) {
		const uint8_t * const bytes = [m_data bytes];
		const size_t numberOfBytes = [m_data length];
		size_t offset = 0;
		size_t value = 0;
		if (MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &value)) {
			if ((SIZE_MAX - offset >= value) && (offset + value == numberOfBytes)) {
				dataValue = [NSData dataWithBytes:bytes + offset length:value];
			}
		}
	}
	return dataValue;
}


- (instancetype)copyWithZone:(NSZone *)zone {
	return [[[self class] alloc] initWithData:m_data ofType:m_type forKeyIndex:m_keyIndex];
}

- (BOOL)isEqual:(id)object {
	BOOL isEqual = (self == object);
	if (!isEqual && [object isKindOfClass:[MMNibArchiveValue class]]) {
		__unsafe_unretained MMNibArchiveValue *other = object;
		isEqual = (other->m_keyIndex == m_keyIndex) && (other->m_type == m_type);
		if (isEqual) {
			__unsafe_unretained NSData * const data = m_data;
			__unsafe_unretained NSData * const other_data = other->m_data;
			isEqual = [other_data isEqual:data];
		}
	}
	return isEqual;
}

- (NSUInteger)hash {
	if (!m_hasCalculatedHash) {
		m_hasCalculatedHash = YES;
		m_hash = (m_keyIndex * 31 + m_type) ^ [self.data hash];
	}
	return m_hash;
}

#ifndef NDEBUG
- (NSString *)debugDescription {
	return [NSString stringWithFormat:@"<%@ %p, t=%jd, kI=%ju>", NSStringFromClass([self class]), self, (intmax_t)m_type, (uintmax_t)m_keyIndex];
}
#endif

@end
