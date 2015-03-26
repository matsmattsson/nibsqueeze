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

#import "StripUnusedClassNames.h"

#import "MMMacros.h"

MMNibArchive * StripUnusedClassNames(MMNibArchive *archive) {
	MMNibArchive *result = archive;

	NSArray * const oldClassNames = archive.classNames;
	NSUInteger const oldNumberOfClassNames = oldClassNames.count;

	if (oldNumberOfClassNames <= SIZE_MAX) {
		BOOL *isUsedOldClassName = calloc(sizeof *isUsedOldClassName, oldNumberOfClassNames);
		if (isUsedOldClassName) {
			NSArray * const oldObjcets = archive.objects;

			for (MMNibArchiveObject *object in oldObjcets) {
				NSUInteger const classNameIndex = object.classNameIndex;
				if (classNameIndex < oldNumberOfClassNames) {
					isUsedOldClassName[classNameIndex] = YES;
				}
			}

			BOOL hasUnusedClassName = NO;
			for (NSUInteger i = 0; i < oldNumberOfClassNames; ++i) {
				if (!isUsedOldClassName[i]) {
					hasUnusedClassName = YES;
					break;
				}
			}

			if (hasUnusedClassName) {
				NSUInteger *indexTranslationTable = calloc(sizeof *indexTranslationTable, oldNumberOfClassNames);

				if (indexTranslationTable) {
					for (size_t i = 0, newClassNameIndex = 0; i < oldNumberOfClassNames; ++i) {
						if (isUsedOldClassName[i]) {
							indexTranslationTable[i] = newClassNameIndex;
							++newClassNameIndex;
						}
					}

					NSMutableArray *newObjects = [NSMutableArray arrayWithCapacity:oldObjcets.count];

					for (MMNibArchiveObject *object in oldObjcets) {
						NSUInteger const oldClassNameIndex = object.classNameIndex;
						NSRange const valueRange = object.valuesRange;
						NSUInteger const newClassNameIndex = indexTranslationTable[oldClassNameIndex];
						MMNibArchiveObject *newObject = [[MMNibArchiveObject alloc] initWithClassNameIndex:newClassNameIndex valuesRange:valueRange];
						[newObjects addObject:newObject];
						MM_release(newObject);
					}

					NSMutableArray *newClassNames = [NSMutableArray arrayWithCapacity:oldNumberOfClassNames];

					for (NSUInteger i = 0; i < oldNumberOfClassNames; ++i) {
						if (isUsedOldClassName[i]) {
							[newClassNames addObject:[oldClassNames objectAtIndex:i]];
						}
					}

					NSError *error = nil;
					MMNibArchive *updatedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:newObjects keys:archive.keys values:archive.values classNames:newClassNames error:&error]);
					if (updatedArchive) {
						result = updatedArchive;
					}

					free(indexTranslationTable);
				}
			}

			free(isUsedOldClassName);
		}
	}

	return result;
}
