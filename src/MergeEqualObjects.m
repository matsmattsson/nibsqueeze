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

#import "MergeEqualObjects.h"

#import "MMMacros.h"

@interface MMNibArchiveObjectEncoding : NSObject
@property (readonly, nonatomic, strong) MMNibArchive *archive;
@property (readonly, nonatomic) NSUInteger objectIndex;
@property (readonly, nonatomic) NSArray *values;

@end

@implementation MMNibArchiveObjectEncoding
- (instancetype)initWithObjectAtIndex:(NSUInteger)objectIndex inNibArchive:(MMNibArchive *)archive {
	self = [super init];
	if (self) {
		_archive = MM_retain(archive);
		_objectIndex = objectIndex;

	}
	return self;
}

- (void)dealloc {
	MM_release(_archive);
	MM_super_dealloc;
}

- (NSArray *)values {
	MMNibArchiveObject *object = [self.archive.objects objectAtIndex:self.objectIndex];
	NSArray *values = [self.archive.values subarrayWithRange:object.valuesRange];
	return values;
}

- (NSUInteger)hash {
	return [self.values hash];
}

- (BOOL)isEqual:(id)object {
	BOOL isEqual = [super isEqual:object];

	if (!isEqual && [object isKindOfClass:[MMNibArchiveObjectEncoding class]]) {
		MMNibArchiveObjectEncoding *other = object;
		isEqual = [self.values isEqual:other.values];
	}

	return isEqual;
}

@end

MMNibArchive * MergeEqualObjects(MMNibArchive *archive) {
	MMNibArchive *result = archive;

	NSMutableDictionary * const duplicateValuesTable = [NSMutableDictionary dictionary];
	NSArray * const oldObjects = archive.objects;
	NSUInteger const numberOfOldObjects = oldObjects.count;
	NSMutableSet * const objectValues = [NSMutableSet setWithCapacity:numberOfOldObjects];

	for (NSUInteger i = 0; i < numberOfOldObjects; ++i) {
		MMNibArchiveObjectEncoding * const encoding = [[MMNibArchiveObjectEncoding alloc] initWithObjectAtIndex:i inNibArchive:archive];
		MMNibArchiveObjectEncoding * const duplicate = [objectValues member:encoding];
		if (duplicate) {
			MMNibArchiveObject * const duplicateObject = [oldObjects objectAtIndex:duplicate.objectIndex];
			[duplicateValuesTable setObject:[NSValue valueWithRange:duplicateObject.valuesRange] forKey:@(i)];
		} else {
			[objectValues addObject:encoding];
		}
		MM_release(encoding);
	}

	if (0 < duplicateValuesTable.count) {
		NSMutableArray * const newObjects = [NSMutableArray arrayWithCapacity:numberOfOldObjects];

		for (NSUInteger i = 0; i < numberOfOldObjects; ++i) {
			MMNibArchiveObject * object = [oldObjects objectAtIndex:i];
			MMNibArchiveObject * newObject = nil;
			NSValue *valueRange = [duplicateValuesTable objectForKey:@(i)];
			if (valueRange) {
				newObject = [[MMNibArchiveObject alloc] initWithClassNameIndex:object.classNameIndex valuesRange:[valueRange rangeValue]];
				object = newObject;
			}
			[newObjects addObject:object];
			MM_release(newObject);
		}

		NSError *error = nil;
		MMNibArchive *mergedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:newObjects keys:archive.keys values:archive.values classNames:archive.classNames error:&error]);
		NSCAssert(mergedArchive, @"Error: %@", error);
		if (mergedArchive) {
			result = mergedArchive;
		}
	}

	return result;
}
