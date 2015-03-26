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

#import "DeduplicateConstantObjects.h"

#import "MMMacros.h"

static const char * const ConstantClassNames[] = {
	"NSAttributedString",
	"NSArray",
	"NSColor",
	"NSDictionary",
	"NSFont",
	"NSNumber",
	"NSSet",
	"NSString",
	"NSValue",
	"UIColor",
	"UIFont",
};

@interface MMNibArchiveDeduplicateConstantObjectsItem : NSObject
@property (nonatomic, strong, readonly) MMNibArchive *archive;
@property (nonatomic, readonly) NSUInteger objectIndex;
@property (nonatomic, readonly) MMNibArchiveClassName *className;
- (instancetype)initWithObjectIndex:(NSUInteger)objectIndex inArchive:(MMNibArchive *)archive;
@end

@implementation MMNibArchiveDeduplicateConstantObjectsItem
@synthesize archive = m_archive;
@synthesize objectIndex = m_objectIndex;

- (void)dealloc {
	MM_release(m_archive);
	MM_super_dealloc;
}

- (instancetype)initWithObjectIndex:(NSUInteger)objectIndex inArchive:(MMNibArchive *)archive {
	NSParameterAssert(archive);
	NSParameterAssert(objectIndex < archive.objects.count);

	self = [super init];
	if (self) {
		if (archive && (objectIndex < archive.objects.count)) {
			m_archive = MM_retain(archive);
			m_objectIndex = objectIndex;
		} else {
			MM_release(self);
			self = nil;
		}
	}
	return self;
}

- (MMNibArchiveClassName *)className {
	MMNibArchive *archive = self.archive;
	MMNibArchiveObject * const archivedObject = [archive.objects objectAtIndex:self.objectIndex];
	MMNibArchiveClassName * const archivedClassName = [archive.classNames objectAtIndex:archivedObject.classNameIndex];
	return archivedClassName;
}

- (BOOL)isEqual:(id)object {
	BOOL isEqual = [super isEqual:object];

	if (!isEqual && [object isKindOfClass:[MMNibArchiveDeduplicateConstantObjectsItem class]]) {
		MMNibArchiveDeduplicateConstantObjectsItem *other = object;

		if (other.archive == self.archive) {
			MMNibArchiveObject * const archivedObject = [self.archive.objects objectAtIndex:self.objectIndex];
			MMNibArchiveObject * const otherArchivedObject = [other.archive.objects objectAtIndex:other.objectIndex];
			MMNibArchiveClassName * const archivedClassName = [self.archive.classNames objectAtIndex:archivedObject.classNameIndex];
			MMNibArchiveClassName * const otherArchivedClassName = [other.archive.classNames objectAtIndex:otherArchivedObject.classNameIndex];

			if ([archivedClassName isEqual:otherArchivedClassName]) {
				NSRange const archivedValuesRange = archivedObject.valuesRange;
				NSRange const otherArchivedValuesRange = otherArchivedObject.valuesRange;
				if (archivedValuesRange.length == otherArchivedValuesRange.length) {
					BOOL hasFoundDistinctValues = NO;
					for (NSUInteger i = 0; i < archivedValuesRange.length; ++i) {
						MMNibArchiveValue *archivedValue = [self.archive.values objectAtIndex:archivedValuesRange.location + i];
						MMNibArchiveValue *otherArchivedValue = [other.archive.values objectAtIndex:otherArchivedValuesRange.location + i];
						if (![archivedValue isEqual:otherArchivedValue]) {
							hasFoundDistinctValues = YES;
							break;
						}
					}

					if (!hasFoundDistinctValues) {
						isEqual = YES;
					}
				}
			}
		}
	}

	return isEqual;
}

- (NSUInteger)hash {
	MMNibArchive *archive = self.archive;
	MMNibArchiveObject * const archivedObject = [archive.objects objectAtIndex:self.objectIndex];
	MMNibArchiveClassName * const archivedClassName = [archive.classNames objectAtIndex:archivedObject.classNameIndex];
	NSRange const archivedValuesRange = archivedObject.valuesRange;
	NSArray * const archivedValues = [archive.values subarrayWithRange:archivedValuesRange];

	NSUInteger const archiveHash = archive.hash;
	NSUInteger const archivedClassNameHash = archivedClassName.hash;
	NSUInteger const archivedValuesHash = archivedValues.hash;

	return archiveHash ^ archivedClassNameHash ^ archivedValuesHash;
}

@end

static NSSet * constantClassNamesSet(void) {
	NSMutableSet * const constantClassNames = [NSMutableSet setWithCapacity:sizeof(ConstantClassNames)/sizeof(ConstantClassNames[0])];
	for ( size_t i = 0; i < sizeof(ConstantClassNames)/sizeof(ConstantClassNames[0]); ++i) {
		NSString *name = [NSString stringWithUTF8String:ConstantClassNames[i]];
		[constantClassNames addObject:name];
	}
	return constantClassNames;
}

static NSDictionary *findIndexesOfDuplicateObjects(MMNibArchive *archive) {
	NSSet * const constantClassNames = constantClassNamesSet();

	NSMutableDictionary * const duplicateTable = [NSMutableDictionary dictionary];

	NSArray * const objects = archive.objects;
	NSUInteger const numberOfObjects = objects.count;

	BOOL *isObjectReferenced = numberOfObjects <= SIZE_MAX ? calloc(sizeof *isObjectReferenced, numberOfObjects) : NULL;
	if (isObjectReferenced) {
		NSArray * const values = archive.values;
		NSUInteger const numberOfValues = values.count;
		for (NSUInteger i = 0; i < numberOfValues; ++i) {
			MMNibArchiveValue *value = [values objectAtIndex:i];
			if (kMMNibArchiveValueTypeObjectReference == value.type) {
				isObjectReferenced[value.objectReference] = YES;
			}
		}

		NSMutableSet * const objectsWithValues = [NSMutableSet setWithCapacity:numberOfObjects];

		for (NSUInteger i = 0; i < numberOfObjects; ++i) {
			MMNibArchiveDeduplicateConstantObjectsItem *item = [[MMNibArchiveDeduplicateConstantObjectsItem alloc] initWithObjectIndex:i inArchive:archive];
			MMNibArchiveDeduplicateConstantObjectsItem *duplicate = [objectsWithValues member:item];
			if (duplicate) {
				if ([constantClassNames containsObject:duplicate.className.nameString]) {
					if (isObjectReferenced[i]) {
						[duplicateTable setObject:@(duplicate.objectIndex) forKey:@(i)];
					} else if (isObjectReferenced[duplicate.objectIndex]) {
						// Re-organize which object of the duplicates are kept, as the initial guess of the first is not good enough

						// Update all existing edges in the duplicate graph
						for (NSNumber *indexA in [duplicateTable keyEnumerator]) {
							NSNumber *indexB = [duplicateTable objectForKey:indexA];
							if (indexB.unsignedIntegerValue == duplicate.objectIndex) {
								[duplicateTable setObject:@(i) forKey:indexA];
							}
						}

						[duplicateTable setObject:@(i) forKey:@(duplicate.objectIndex)];
						[objectsWithValues removeObject:duplicate];
						[objectsWithValues addObject:item];
					}
				}
			} else {
				[objectsWithValues addObject:item];
			}
			MM_release(item);
		}

		free(isObjectReferenced);
	}

	return duplicateTable;
}

MMNibArchive * DeduplicateConstantObjects(MMNibArchive *archive) {
	MMNibArchive *result = archive;

	while(1) {
		NSArray * const oldObjects = result.objects;
		NSUInteger const numberOfOldObjects = oldObjects.count;

		NSDictionary * const duplicateTable = findIndexesOfDuplicateObjects(result);

		if (0 < duplicateTable.count && numberOfOldObjects <= SIZE_MAX) {
			NSUInteger *objectTranslationTable = calloc(sizeof *objectTranslationTable, numberOfOldObjects);
			if (objectTranslationTable) {

				// Create object index translation table for all objects that are to be kept
				for (NSUInteger i = 0, newObjectIndex = 0; i < numberOfOldObjects; ++i) {
					BOOL const isDuplicateObject = (nil != [duplicateTable objectForKey:@(i)]);
					if (!isDuplicateObject) {
						objectTranslationTable[i] = newObjectIndex;
						++newObjectIndex;
					}
				}

				// Update translation table for duplicate objects, so they point at the remaining duplicate
				for (NSNumber *duplicateObjectIndex in [duplicateTable keyEnumerator]) {
					NSNumber *oldKeptObjectIndex = [duplicateTable objectForKey:duplicateObjectIndex];
					objectTranslationTable[duplicateObjectIndex.unsignedIntegerValue] = objectTranslationTable[oldKeptObjectIndex.unsignedIntegerValue];
				}

				// Remove duplicate objects
				NSMutableArray *newObjects = [NSMutableArray arrayWithCapacity:numberOfOldObjects];
				for (NSUInteger i = 0; i < numberOfOldObjects; ++i) {
					BOOL const isDuplicateObject = (nil != [duplicateTable objectForKey:@(i)]);
					MMNibArchiveObject *object = [oldObjects objectAtIndex:i];
					if (!isDuplicateObject) {
						[newObjects addObject:object];
					}
				}
				NSCAssert(newObjects.count + duplicateTable.count <= numberOfOldObjects, @"Added too few objects.");
				NSCAssert(newObjects.count + duplicateTable.count >= numberOfOldObjects, @"Added too many objects.");

				// Create new values for updated object references
				NSMutableArray *newValues = [NSMutableArray arrayWithCapacity:result.values.count];
				for (MMNibArchiveValue *value in result.values) {
					MMNibArchiveValue *updatedValue = value;
					if (kMMNibArchiveValueTypeObjectReference == value.type) {
						uint32_t const oldObjectReference = value.objectReference;
						uint32_t const newObjectReference = (uint32_t)objectTranslationTable[oldObjectReference];
						NSCAssert(newObjectReference < newObjects.count, @"Reference to nonexisting object.");
						if (oldObjectReference != newObjectReference) {
							updatedValue = [[MMNibArchiveValue alloc] initWithObjectReference:newObjectReference forKeyIndex:value.keyIndex];
						}
					}
					[newValues addObject:updatedValue];
				}

				NSError *error = nil;
				MMNibArchive *deduplicatedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:newObjects keys:result.keys values:newValues classNames:result.classNames error:&error]);
				NSCAssert(deduplicatedArchive, @"Error creating deduplicated archive: %@", error);

				free(objectTranslationTable);
				objectTranslationTable = nil;


				if (deduplicatedArchive) {
					result = deduplicatedArchive;
				} else {
					// error creating deduplicated archive
					break;
				}
			} else {
				// calloc error
				break;
			}
		} else {
			// no more duplicates
			break;
		}
	}

	return result;
}
