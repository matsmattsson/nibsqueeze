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

#import "MMNibArchive.h"

#import "MMMacros.h"

#include <string.h>

static const unsigned char NibFileMagic[] = {'N', 'I', 'B', 'A', 'r', 'c', 'h', 'i', 'v', 'e'};

static const unsigned char EmptyNibArchive[] = {
	'N', 'I', 'B', 'A', 'r', 'c', 'h', 'i', 'v', 'e', // Magic number
	0x01, 0x00, 0x00, 0x00, // (?) Major version
	0x09, 0x00, 0x00, 0x00, // (?) Minor version
	0x00, 0x00, 0x00, 0x00, // Object count
	0x32, 0x00, 0x00, 0x00, // Object list file offset
	0x00, 0x00, 0x00, 0x00, // Key count
	0x32, 0x00, 0x00, 0x00, // Key list file offset
	0x00, 0x00, 0x00, 0x00, // Value count
	0x32, 0x00, 0x00, 0x00, // Value list file offset
	0x00, 0x00, 0x00, 0x00, // Class name count
	0x32, 0x00, 0x00, 0x00, // Class name list file offset
};

NSString * const MMNibArchiveErrorDomain = @"MMNibArchive";

#define kMMNibArchiveHeaderSize (sizeof(EmptyNibArchive))

BOOL MMNibArchiveReadVarLengthInteger(const uint8_t * const bytes, const size_t numberOfBytes, size_t *offsetPtr, size_t *resultPtr) {
	size_t offset = *offsetPtr;
	size_t result = 0;
	size_t digitIndex = 0;
	BOOL success = NO;

	while(bytes && offset < numberOfBytes) {
		const uint8_t b = bytes[offset]; ++offset;
		const uint8_t digit = 0x7f & b;
		const BOOL isLastDigit = (0 != (0x80 & b));

		const size_t shiftAmount = 7 * digitIndex;
		++digitIndex;

		if (shiftAmount < CHAR_BIT * sizeof(result)) {
			const size_t validBits = ~(size_t)0 >> shiftAmount;
			const BOOL hasInvalidBits = (0 != (~validBits & digit));
			if (!hasInvalidBits) {
				result = result | (digit << shiftAmount);
				success = isLastDigit;
			}
		}

		if (isLastDigit) {
			break;
		}
	}

	*offsetPtr = offset;
	*resultPtr = result;

	return success;
}

size_t MMNibArchiveSerializedLengthForInteger(size_t value) {
	size_t size = 0;
	do {
		++size;
		value = value >> 7;
	} while(value != 0);

	return size;
}

BOOL MMNibArchiveWriteVarLengthInteger(uint8_t * const bytes, const size_t numberOfBytes, size_t *offsetPtr, size_t value) {
	size_t offset = *offsetPtr;
	size_t v = value;

	BOOL success = NO;

	while(bytes && offset < numberOfBytes) {
		const uint8_t digit = 0x7f & v;
		v = v >> 7;
		const BOOL isLastDigit = (0 == v);
		bytes[offset] = digit | (isLastDigit ? 0x80 : 0); ++offset;

		if (isLastDigit) {
			success = YES;
			break;
		}
	}

	*offsetPtr = offset;

	return success;
}

static void validateNibArchiveObjectList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t objectCount, const uint32_t objectFileOffset, const uint32_t valueCount, const uint32_t classNameCount, NSError **errorPtr) {
	NSError *error = nil;

	if (objectFileOffset < kMMNibArchiveHeaderSize || objectFileOffset > numberOfBytes) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	size_t offset = objectFileOffset;

	for (size_t objectIndex = 0; !error && objectIndex < objectCount; ++objectIndex) {
		size_t classNameIndex = 0;
		size_t objectValuesOffset = 0;
		size_t objectValuesCount = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &classNameIndex)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadClassNameIndex userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &objectValuesOffset)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadValuesOffset userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &objectValuesCount)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadValuesCount userInfo:nil];
		}

		if (!error && !(classNameIndex < classNameCount)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidClassNameIndex userInfo:nil];
		}

		if (!error && !(objectValuesOffset < valueCount)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidValuesOffset userInfo:nil];
		}

		if (!error && !(objectValuesCount <= valueCount && objectValuesOffset <= (valueCount - objectValuesCount))) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidValuesCount userInfo:nil];
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}
}

static NSArray *nibArchiveObjectList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t objectCount, const uint32_t objectFileOffset, NSError **errorPtr) {
	NSError *error = nil;
	NSMutableArray *objects = [NSMutableArray array];

	size_t offset = objectFileOffset;

	for (size_t objectIndex = 0; !error && objectIndex < objectCount; ++objectIndex) {
		size_t classNameIndex = 0;
		size_t objectValuesOffset = 0;
		size_t objectValuesCount = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &classNameIndex)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadClassNameIndex userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &objectValuesOffset)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadValuesOffset userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &objectValuesCount)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectReadValuesCount userInfo:nil];
		}

		if (!error) {
			MMNibArchiveObject *object = [[MMNibArchiveObject alloc] initWithClassNameIndex:classNameIndex valuesRange:NSMakeRange(objectValuesOffset, objectValuesCount)];
			[objects addObject:object];
			MM_release(object);
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return error ? nil : [objects copy];
}

static NSData *serializeNibArchiveObjectList(NSArray *objects) {
	size_t dataSize = 0;
	NSData *data = nil;

	for (MMNibArchiveObject *object in objects) {
		const NSUInteger classNameIndex = object.classNameIndex;
		const NSRange valuesRange = object.valuesRange;
		const size_t classNameIndexLength = MMNibArchiveSerializedLengthForInteger(classNameIndex);

		if ( dataSize <= SIZE_MAX - classNameIndexLength) {
			dataSize = dataSize + classNameIndexLength;
		} else {
			dataSize = SIZE_MAX;
		}

		const size_t valueOffsetLength = MMNibArchiveSerializedLengthForInteger(valuesRange.location);

		if ( dataSize <= SIZE_MAX - valueOffsetLength) {
			dataSize = dataSize + valueOffsetLength;
		} else {
			dataSize = SIZE_MAX;
		}

		const size_t valueCountLength = MMNibArchiveSerializedLengthForInteger(valuesRange.length);

		if ( dataSize <= SIZE_MAX - valueCountLength) {
			dataSize = dataSize + valueCountLength;
		} else {
			dataSize = SIZE_MAX;
		}
	}

	if ( dataSize < SIZE_MAX) {
		NSMutableData *mutableData = [NSMutableData dataWithLength:dataSize];
		uint8_t * const bytes = [mutableData mutableBytes];
		size_t offset = 0;
		BOOL success = YES;

		for (MMNibArchiveObject *object in objects) {
			const NSUInteger classNameIndex = object.classNameIndex;
			const NSRange valuesRange = object.valuesRange;

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, classNameIndex);
			}

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, valuesRange.location);
			}

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, valuesRange.length);
			}
		}

		if (success) {
			data = mutableData;
		}
	}

	return data;
}

static void validateNibArchiveKeyList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t keyCount, const uint32_t keyFileOffset, NSError **errorPtr) {
	NSError *error = nil;

	if (keyFileOffset < kMMNibArchiveHeaderSize || keyFileOffset > numberOfBytes) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	size_t offset = keyFileOffset;

	for (size_t keyIndex = 0; !error && keyIndex < keyCount; ++keyIndex) {
		size_t keyLength = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &keyLength)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error) {
			if (offset <= SIZE_MAX - keyLength) {
				offset = offset + keyLength;
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}
}

static NSArray *nibArchiveKeyList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t keyCount, const uint32_t keyFileOffset, NSError **errorPtr) {
	NSError *error = nil;
	NSMutableArray *keys = [NSMutableArray array];

	size_t offset = keyFileOffset;

	for (size_t keyIndex = 0; !error && keyIndex < keyCount; ++keyIndex) {
		size_t keyLength = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &keyLength)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error) {
			if (offset <= SIZE_MAX - keyLength) {
				NSData *key = [NSData dataWithBytes:bytes + offset length:keyLength];
				[keys addObject:key ? key : [NSData data]];

				offset = offset + keyLength;
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return error ? nil : [keys copy];
}

static NSData *serializeNibArchiveKeyList(NSArray *keys) {
	size_t dataSize = 0;
	NSData *data = nil;

	for (NSData *key in keys) {
		const NSUInteger length = [key length];
		const size_t encodedLengthSize = MMNibArchiveSerializedLengthForInteger(length);

		if ( dataSize <= SIZE_MAX - encodedLengthSize) {
			dataSize = dataSize + encodedLengthSize;
		} else {
			dataSize = SIZE_MAX;
		}

		if ( dataSize <= SIZE_MAX - length) {
			dataSize = dataSize + length;
		} else {
			dataSize = SIZE_MAX;
		}
	}

	if (dataSize < SIZE_MAX) {
		NSMutableData *mutableData = [NSMutableData dataWithLength:dataSize];
		uint8_t * const bytes = [mutableData mutableBytes];
		size_t offset = 0;
		BOOL success = YES;

		for (NSData *key in keys) {
			const NSUInteger length = [key length];

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, length);
			}

			if (success) {
				success = offset <= dataSize && length <= (dataSize - offset);
				if (success) {
					memcpy(bytes + offset, [key bytes], length);
					offset += length;
				}
			}
		}

		if (success) {
			data = mutableData;
		}
	}

	return data;
}

static void validateNibArchiveValueList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t valueCount, const uint32_t valueFileOffset, const uint32_t objectCount, const uint32_t keyCount, NSError **errorPtr) {
	NSError *error = nil;

	if (valueFileOffset < kMMNibArchiveHeaderSize || valueFileOffset > numberOfBytes) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	size_t offset = valueFileOffset;

	for (size_t valueIndex = 0; !error && valueIndex < valueCount; ++valueIndex) {
		size_t keyIndex = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &keyIndex)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueReadKeyIndex userInfo:nil];
		}

		if (!error && !(keyIndex < keyCount)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueInvalidKeyIndex userInfo:nil];
		}

		if (!error) {
			if (offset < numberOfBytes) {
				size_t valueLength = 0;
				uint8_t type = bytes[offset]; ++offset;

				switch((enum MMNibArchiveValueType)type) {
					case kMMNibArchiveValueTypeUInt8: {
						valueLength = sizeof(uint8_t) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeUInt16: {
						valueLength = sizeof(uint16_t) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeUInt32: {
						valueLength = sizeof(uint32_t) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeUInt64: {
						valueLength = sizeof(uint64_t) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeTrue: {
					} break;
					case kMMNibArchiveValueTypeFalse: {
					} break;
					case kMMNibArchiveValueTypeFloat: {
						valueLength = sizeof(float) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeDouble: {
						valueLength = sizeof(double) / sizeof(uint8_t);
					} break;
					case kMMNibArchiveValueTypeNil: {
					} break;
					case kMMNibArchiveValueTypeData: {
						if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &valueLength)) {
							error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
						}
					} break;
					case kMMNibArchiveValueTypeObjectReference: {
						valueLength = sizeof(uint32_t) / sizeof(uint8_t);

						if (offset <= SIZE_MAX - valueLength && offset + valueLength <= numberOfBytes) {
							uint32_t v = 0;
							memcpy(&v, bytes + offset, sizeof(v));
							if (!error && !(v < objectCount)) {
								error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueInvalidObjectReference userInfo:nil];
							}
						}
					} break;
					default: {
						if (!error) {
							error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueReadType userInfo:nil];
						}
					} break;
				}

				if (!error) {
					if (offset <= SIZE_MAX - valueLength && offset + valueLength <= numberOfBytes) {
						offset = offset + valueLength;
					} else {
						error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
					}
				}
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}
}

static NSArray *nibArchiveValueList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t valueCount, const uint32_t valueFileOffset, NSError **errorPtr) {
	NSError *error = nil;
	NSMutableArray *values = [NSMutableArray array];

	if (valueFileOffset < kMMNibArchiveHeaderSize || valueFileOffset > numberOfBytes) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	size_t offset = valueFileOffset;

	for (size_t valueIndex = 0; !error && valueIndex < valueCount; ++valueIndex) {
		size_t keyIndex = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &keyIndex)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error && offset < numberOfBytes) {
			size_t valueLength = 0;
			uint8_t type = bytes[offset]; ++offset;
			const size_t valueOffsetStart = offset;

			switch((enum MMNibArchiveValueType)type) {
				case kMMNibArchiveValueTypeUInt8: {
					valueLength = sizeof(uint8_t) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeUInt16: {
					valueLength = sizeof(uint16_t) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeUInt32: {
					valueLength = sizeof(uint32_t) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeUInt64: {
					valueLength = sizeof(uint64_t) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeTrue: {
				} break;
				case kMMNibArchiveValueTypeFalse: {
				} break;
				case kMMNibArchiveValueTypeFloat: {
					valueLength = sizeof(float) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeDouble: {
					valueLength = sizeof(double) / sizeof(uint8_t);
				} break;
				case kMMNibArchiveValueTypeData: {
					if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &valueLength)) {
						error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
					}
				} break;
				case kMMNibArchiveValueTypeNil: {
				} break;
				case kMMNibArchiveValueTypeObjectReference: {
					valueLength = sizeof(uint32_t) / sizeof(uint8_t);
				} break;
				default: {
					if (!error) {
						error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
					}
				} break;
			}

			if (!error) {
				if (offset <= SIZE_MAX - valueLength) {
					NSData *data = [NSData dataWithBytes:bytes + valueOffsetStart length:offset - valueOffsetStart + valueLength];
					MMNibArchiveValue *value = [[MMNibArchiveValue alloc] initWithData:data ofType:type forKeyIndex:keyIndex];
					[values addObject:value];

					offset = offset + valueLength;
					MM_release(value);
				} else {
					error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
				}
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return error ? nil : [values copy];
}

static NSData *serializeNibArchiveValuesList(NSArray *values) {
	size_t dataSize = 0;
	NSData *data = nil;

	for (MMNibArchiveValue *value in values) {
		const NSUInteger keyIndex = value.keyIndex;
		const uint8_t type;
		NSData *const data = value.data;
		const NSUInteger valueLength = [data length];

		const size_t encodedKeyIndexSize = MMNibArchiveSerializedLengthForInteger(keyIndex);

		if ( dataSize <= SIZE_MAX - encodedKeyIndexSize) {
			dataSize = dataSize + encodedKeyIndexSize;
		} else {
			dataSize = SIZE_MAX;
		}

		if ( dataSize <= SIZE_MAX - sizeof(type)) {
			dataSize = dataSize + sizeof(type);
		} else {
			dataSize = SIZE_MAX;
		}

		if ( dataSize <= SIZE_MAX - valueLength) {
			dataSize = dataSize + valueLength;
		} else {
			dataSize = SIZE_MAX;
		}
	}

	if (dataSize < SIZE_MAX) {
		NSMutableData *mutableData = [NSMutableData dataWithLength:dataSize];
		uint8_t * const bytes = [mutableData mutableBytes];
		size_t offset = 0;
		BOOL success = YES;

		for (MMNibArchiveValue *value in values) {
			const NSUInteger keyIndex = value.keyIndex;
			const uint8_t type = value.type;
			NSData *const valueData = value.data;
			const NSUInteger valueLength = [valueData length];

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, keyIndex);
			}

			if (success && offset < dataSize) {
				bytes[offset] = type;
				++offset;
			}

			if (success) {
				success = offset <= dataSize && valueLength <= (dataSize - offset);
				if (success) {
					memcpy(bytes + offset, [valueData bytes], valueLength);
					offset += valueLength;
				}
			}
		}

		if (success) {
			data = mutableData;
		}
	}

	return data;
}

static void validateNibArchiveClassNameList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t classNameCount, const uint32_t classNameFileOffset, NSError **errorPtr) {
	NSError *error = nil;

	if (classNameFileOffset < kMMNibArchiveHeaderSize || classNameFileOffset > numberOfBytes) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	size_t offset = classNameFileOffset;

	for (size_t classNameIndex = 0; !error && classNameIndex < classNameCount; ++classNameIndex) {
		size_t classNameLength = 0;
		size_t uint32Count = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &classNameLength)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &uint32Count)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error) {
			const size_t maxUint32Count = SIZE_MAX / (sizeof(uint32_t)/sizeof(uint8_t));
			if (uint32Count <= maxUint32Count && offset <= SIZE_MAX - uint32Count * (sizeof(uint32_t)/sizeof(uint8_t))) {
				offset = offset + uint32Count * (sizeof(uint32_t)/sizeof(uint8_t));
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}

		if (!error) {
			if (offset <= SIZE_MAX - classNameLength) {
				offset = offset + classNameLength;
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}
}

static NSArray *nibArchiveClassNameList(const uint8_t * const bytes, const size_t numberOfBytes, const uint32_t classNameCount, const uint32_t classNameFileOffset, NSError **errorPtr) {
	NSError *error = nil;
	NSMutableArray *classNames = [NSMutableArray array];
	size_t offset = classNameFileOffset;

	for (size_t classNameIndex = 0; !error && classNameIndex < classNameCount; ++classNameIndex) {
		size_t classNameLength = 0;
		size_t uint32Count = 0;

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &classNameLength)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		if (!error && !MMNibArchiveReadVarLengthInteger(bytes, numberOfBytes, &offset, &uint32Count)) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
		}

		NSMutableArray *integers = nil;

		if (!error) {
			const size_t maxUint32Count = SIZE_MAX / (sizeof(uint32_t)/sizeof(uint8_t));
			if (uint32Count <= maxUint32Count && offset <= SIZE_MAX - uint32Count * (sizeof(uint32_t)/sizeof(uint8_t))) {
				integers = 0 < uint32Count ? [NSMutableArray array] : nil;
				for (size_t i = 0; i < uint32Count; ++i) {
					uint32_t v = 0;
					memcpy(&v, bytes + offset + i * (sizeof(v)/sizeof(uint8_t)), sizeof(v));
					[integers addObject:[NSNumber numberWithUnsignedLongLong:CFSwapInt32LittleToHost(v)]];
				}

				offset = offset + uint32Count * (sizeof(uint32_t)/sizeof(uint8_t));
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}

		if (!error) {
			if (offset <= SIZE_MAX - classNameLength) {
				NSData *name = [NSData dataWithBytes:bytes + offset length:classNameLength];
				MMNibArchiveClassName *className = [[MMNibArchiveClassName alloc] initWithName:name integers:integers];
				[classNames addObject:className];

				offset = offset + classNameLength;
				MM_release(className);
			} else {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidData userInfo:nil];
			}
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return error ? nil : [classNames copy];
}

static NSData *serializeNibArchiveClassNameList(NSArray *classNames) {
	size_t dataSize = 0;
	NSData *data = nil;

	for (MMNibArchiveClassName *className in classNames) {
		NSData *const name = className.name;
		const NSUInteger nameLength = [name length];
		NSArray * const integers = className.integers;
		const NSUInteger numberOfIntegers = [integers count];

		const size_t encodedNameLengthSize = MMNibArchiveSerializedLengthForInteger(nameLength);

		if ( dataSize <= SIZE_MAX - encodedNameLengthSize) {
			dataSize = dataSize + encodedNameLengthSize;
		} else {
			dataSize = SIZE_MAX;
		}

		const size_t encodedNumberOfIntegersSize = MMNibArchiveSerializedLengthForInteger(numberOfIntegers);

		if ( dataSize <= SIZE_MAX - encodedNumberOfIntegersSize) {
			dataSize = dataSize + encodedNumberOfIntegersSize;
		} else {
			dataSize = SIZE_MAX;
		}

		if ( dataSize <= SIZE_MAX - numberOfIntegers * sizeof(uint32_t) && numberOfIntegers <= SIZE_MAX / sizeof(uint32_t)) {
			dataSize = dataSize + numberOfIntegers * sizeof(uint32_t);
		} else {
			dataSize = SIZE_MAX;
		}

		if ( dataSize <= SIZE_MAX - nameLength) {
			dataSize = dataSize + nameLength;
		} else {
			dataSize = SIZE_MAX;
		}
	}

	if (dataSize < SIZE_MAX) {
		NSMutableData *mutableData = [NSMutableData dataWithLength:dataSize];
		uint8_t * const bytes = [mutableData mutableBytes];
		size_t offset = 0;
		BOOL success = YES;

		for (MMNibArchiveClassName *className in classNames) {
			NSData *const name = className.name;
			const NSUInteger nameLength = [name length];
			NSArray * const integers = className.integers;
			const NSUInteger numberOfIntegers = [integers count];

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, nameLength);
			}

			if (success) {
				success = MMNibArchiveWriteVarLengthInteger(bytes, dataSize, &offset, numberOfIntegers);
			}

			for (size_t i = 0; success && i < numberOfIntegers; ++i) {
				const uint32_t v = CFSwapInt32HostToLittle((uint32_t)[[integers objectAtIndex:i] unsignedLongLongValue]);
				if ( offset <= dataSize && sizeof(uint32_t) <= dataSize - offset) {
					memcpy(bytes + offset, &v, sizeof(v));
					offset += sizeof(v);
				}
			}

			if (success) {
				success = offset <= dataSize && nameLength <= (dataSize - offset);
				if (success) {
					memcpy(bytes + offset, [name bytes], nameLength);
					offset += nameLength;
				}
			}
		}

		if (success) {
			data = mutableData;
		}
	}
	
	return data;
}

@implementation MMNibArchive
@synthesize data = m_data;
@synthesize keys = m_keys;
@synthesize values = m_values;
@synthesize objects = m_objects;
@synthesize classNames = m_classNames;


- (void)dealloc {
	MM_release(m_data);
	MM_release(m_keys);
	MM_release(m_values);
	MM_release(m_objects);
	MM_release(m_classNames);
	
	MM_super_dealloc;
}

- (instancetype)init {
	return [self initWithData:[NSData dataWithBytes:EmptyNibArchive length:sizeof(EmptyNibArchive)] error:NULL];
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)errorPtr {
	self = [super init];
	if (self) {
		const BOOL isValidNibArchive = [[self class] isValidNibArchiveData:data error:errorPtr];
		if (isValidNibArchive) {
			m_data = [data copy];
		} else {
			self = nil;
		}
	}
	return self;
}

- (instancetype)initWithObjects:(NSArray *)objects keys:(NSArray *)keys values:(NSArray *)values classNames:(NSArray *)classNames error:(NSError **)errorPtr {
	self = [super init];
	if (self) {
		const BOOL isValidObjects = [[self class] isValidObjects:objects keys:keys values:values classNames:classNames error:errorPtr];
		if (isValidObjects) {
			m_objects = [[NSArray alloc] initWithArray:objects copyItems:YES];
			m_keys = [[NSArray alloc] initWithArray:keys copyItems:YES];
			m_values = [[NSArray alloc] initWithArray:values copyItems:YES];
			m_classNames = [[NSArray alloc] initWithArray:classNames copyItems:YES];
		} else {
			self = nil;
		}
	}
	return self;
}

#pragma mark Validate

+ (BOOL)isValidNibArchiveData:(NSData *)data error:(NSError **)errorPtr {
	NSError *error = nil;

	const NSUInteger numberOfBytes = [data length];
	const uint8_t * const bytes = [data bytes];

	if (!error && numberOfBytes < kMMNibArchiveHeaderSize) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	if (!error && (0 != memcmp(NibFileMagic, bytes, sizeof(NibFileMagic)))) {
		error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
	}

	if (!error) {
		uint32_t headerValues[10];
		memcpy(headerValues, bytes + sizeof(NibFileMagic), sizeof(headerValues));
		const uint32_t majorVersion = CFSwapInt32LittleToHost(headerValues[0]);
		const uint32_t minorVersion = CFSwapInt32LittleToHost(headerValues[1]);
		const uint32_t objectCount = CFSwapInt32LittleToHost(headerValues[2]);
		const uint32_t objectFileOffset = CFSwapInt32LittleToHost(headerValues[3]);
		const uint32_t keyCount = CFSwapInt32LittleToHost(headerValues[4]);
		const uint32_t keyFileOffset = CFSwapInt32LittleToHost(headerValues[5]);
		const uint32_t valueCount = CFSwapInt32LittleToHost(headerValues[6]);
		const uint32_t valueFileOffset = CFSwapInt32LittleToHost(headerValues[7]);
		const uint32_t classNameCount = CFSwapInt32LittleToHost(headerValues[8]);
		const uint32_t classNameFileOffset = CFSwapInt32LittleToHost(headerValues[9]);

		if (!error && kMMNibArchiveHeaderMajorVersion != majorVersion) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
		}

		if (!error && kMMNibArchiveHeaderMinorVersion != minorVersion) {
			error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorInvalidHeader userInfo:nil];
		}

		if (!error) {
			validateNibArchiveObjectList(bytes, numberOfBytes, objectCount, objectFileOffset, valueCount, classNameCount, &error);
		}

		if (!error) {
			validateNibArchiveKeyList(bytes, numberOfBytes, keyCount, keyFileOffset, &error);
		}

		if (!error) {
			validateNibArchiveValueList(bytes, numberOfBytes, valueCount, valueFileOffset, objectCount, keyCount, &error);
		}

		if (!error) {
			validateNibArchiveClassNameList(bytes, numberOfBytes, classNameCount, classNameFileOffset, &error);
		}
	}

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return !error;
}

+ (BOOL)isValidObjects:(NSArray *)objects keys:(NSArray *)keys values:(NSArray *)values classNames:(NSArray *)classNames error:(NSError **)errorPtr {
	NSError *error = nil;

	const NSUInteger numberOfObjects = objects.count;
	const NSUInteger numberOfKeys = keys.count;
	const NSUInteger numberOfValues = values.count;
	const NSUInteger numberOfClassNames = classNames.count;

	if (!error) {
		for (MMNibArchiveObject *object in objects) {
			if (!error && ![object isKindOfClass:[MMNibArchiveObject class]]) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidClass userInfo:nil];
			}

			if (!error && !(object.classNameIndex < numberOfClassNames)) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidClassNameIndex userInfo:nil];
			}

			if (!error && !(object.valuesRange.location < numberOfValues)) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidValuesOffset userInfo:nil];
			}

			if (!error && !(NSMaxRange(object.valuesRange) <= numberOfValues)) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorObjectInvalidValuesCount userInfo:nil];
			}
		}
	}

	if (!error) {
		for (NSData *key in keys) {
			if (!error && ![key isKindOfClass:[NSData class]]) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorKeyInvalidClass userInfo:nil];
			}
		}
	}

	if (!error) {
		for (MMNibArchiveValue *value in values) {
			if (!error && !(value.keyIndex < numberOfKeys)) {
				error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueInvalidKeyIndex userInfo:nil];
			}

			switch (value.type) {
				case kMMNibArchiveValueTypeObjectReference: {
					if (!error && !(value.objectReference < numberOfObjects)) {
						error = [NSError errorWithDomain:MMNibArchiveErrorDomain code:kMMNibArchiveErrorValueInvalidObjectReference userInfo:nil];
					}
				} break;
				default: {
				} break;
			}
		}
	}

	

	if (error && errorPtr) {
		*errorPtr = error;
	}

	return !error;
}

#pragma mark Public properties

- (NSArray *)keys {
	NSData * const data = m_data;
	if (!m_keys && data) {
		const NSUInteger numberOfBytes = [data length];
		const uint8_t * const bytes = [data bytes];

		uint32_t headerValues[2];
		memcpy(headerValues, bytes + sizeof(NibFileMagic) + 4 * sizeof(uint32_t), sizeof(headerValues));
		const uint32_t keyCount = CFSwapInt32LittleToHost(headerValues[0]);
		const uint32_t keyFileOffset = CFSwapInt32LittleToHost(headerValues[1]);
		m_keys = nibArchiveKeyList(bytes, numberOfBytes, keyCount, keyFileOffset, NULL);
	}
	return m_keys;
}

- (NSArray *)values {
	NSData * const data = m_data;
	if (!m_values && data) {
		const NSUInteger numberOfBytes = [data length];
		const uint8_t * const bytes = [data bytes];

		uint32_t headerValues[2];
		memcpy(headerValues, bytes + sizeof(NibFileMagic) + 6 * sizeof(uint32_t), sizeof(headerValues));
		const uint32_t valueCount = CFSwapInt32LittleToHost(headerValues[0]);
		const uint32_t valueFileOffset = CFSwapInt32LittleToHost(headerValues[1]);
		m_values = nibArchiveValueList(bytes, numberOfBytes, valueCount, valueFileOffset, NULL);
	}
	return m_values;
}

- (NSArray *)objects {
	NSData * const data = m_data;
	if (!m_objects && data) {
		const NSUInteger numberOfBytes = [data length];
		const uint8_t * const bytes = [data bytes];

		uint32_t headerValues[2];
		memcpy(headerValues, bytes + sizeof(NibFileMagic) + 2 * sizeof(uint32_t), sizeof(headerValues));
		const uint32_t objectCount = CFSwapInt32LittleToHost(headerValues[0]);
		const uint32_t objectFileOffset = CFSwapInt32LittleToHost(headerValues[1]);
		m_objects = nibArchiveObjectList(bytes, numberOfBytes, objectCount, objectFileOffset, NULL);
	}
	return m_objects;
}

- (NSArray *)classNames {
	NSData * const data = m_data;
	if (!m_classNames && data) {
		const NSUInteger numberOfBytes = [data length];
		const uint8_t * const bytes = [data bytes];

		uint32_t headerValues[2];
		memcpy(headerValues, bytes + sizeof(NibFileMagic) + 8 * sizeof(uint32_t), sizeof(headerValues));
		const uint32_t classNameCount = CFSwapInt32LittleToHost(headerValues[0]);
		const uint32_t classNameFileOffset = CFSwapInt32LittleToHost(headerValues[1]);
		m_classNames = nibArchiveClassNameList(bytes, numberOfBytes, classNameCount, classNameFileOffset, NULL);
	}
	return m_classNames;
}

- (NSData *)data {
	NSArray *objects = m_objects;
	NSArray *keys = m_keys;
	NSArray *values = m_values;
	NSArray *classNames = m_classNames;
	if (!m_data && objects && keys && values && classNames) {

		NSData *objectsData = serializeNibArchiveObjectList(objects);
		NSData *keysData = serializeNibArchiveKeyList(keys);
		NSData *valuesData = serializeNibArchiveValuesList(values);
		NSData *classNamesData = serializeNibArchiveClassNameList(classNames);

		uint32_t headerValues[10] = { 0 };

		headerValues[0] = CFSwapInt32HostToLittle(kMMNibArchiveHeaderMajorVersion);
		headerValues[1] = CFSwapInt32HostToLittle(kMMNibArchiveHeaderMinorVersion);

		size_t dataSize = kMMNibArchiveHeaderSize;

		if ( objectsData && [objectsData length] < SIZE_MAX - dataSize ) {
			dataSize = dataSize + [objectsData length];
		} else {
			dataSize = SIZE_MAX;
		}

		if ( keysData && [keysData length] < SIZE_MAX - dataSize ) {
			dataSize = dataSize + [keysData length];
		} else {
			dataSize = SIZE_MAX;
		}

		if ( valuesData && [valuesData length] < SIZE_MAX - dataSize ) {
			dataSize = dataSize + [valuesData length];
		} else {
			dataSize = SIZE_MAX;
		}

		if ( classNamesData && [classNamesData length] < SIZE_MAX - dataSize ) {
			dataSize = dataSize + [classNamesData length];
		} else {
			dataSize = SIZE_MAX;
		}

		if (dataSize < SIZE_MAX && dataSize < NSUIntegerMax) {
			NSMutableData *mutableData = [NSMutableData dataWithLength:dataSize];
			uint8_t * const bytes = [mutableData mutableBytes];
			size_t offset = kMMNibArchiveHeaderSize;

			memcpy(bytes + offset, [objectsData bytes], [objectsData length]);
			headerValues[2] = CFSwapInt32HostToLittle((uint32_t)[objects count]);
			headerValues[3] = CFSwapInt32HostToLittle((uint32_t)offset);
			offset += [objectsData length];

			memcpy(bytes + offset, [keysData bytes], [keysData length]);
			headerValues[4] = CFSwapInt32HostToLittle((uint32_t)[keys count]);
			headerValues[5] = CFSwapInt32HostToLittle((uint32_t)offset);
			offset += [keysData length];

			memcpy(bytes + offset, [valuesData bytes], [valuesData length]);
			headerValues[6] = CFSwapInt32HostToLittle((uint32_t)[values count]);
			headerValues[7] = CFSwapInt32HostToLittle((uint32_t)offset);
			offset += [valuesData length];

			memcpy(bytes + offset, [classNamesData bytes], [classNamesData length]);
			headerValues[8] = CFSwapInt32HostToLittle((uint32_t)[classNames count]);
			headerValues[9] = CFSwapInt32HostToLittle((uint32_t)offset);
			// offset += [classNamesData length];

			memcpy(bytes, NibFileMagic, sizeof(NibFileMagic));
			memcpy(bytes + sizeof(NibFileMagic), headerValues, sizeof(headerValues));

			m_data = [mutableData copy];
		}
	}
	return m_data;
}

@end
