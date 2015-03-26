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

#import "StripUnusedValues.h"

#import "MMMacros.h"

MMNibArchive * StripUnusedValues(MMNibArchive *archive) {
	MMNibArchive *result = archive;

	NSArray * const oldValues = archive.values;
	NSUInteger const numberOfOldValues = oldValues.count;

	if (numberOfOldValues <= SIZE_MAX) {
		BOOL * const isValueUsed = calloc(sizeof *isValueUsed, numberOfOldValues);

		if (isValueUsed) {

			NSArray * const oldObjects = archive.objects;

			for (MMNibArchiveObject *object in oldObjects) {
				NSRange const valuesRange = object.valuesRange;
				for (NSUInteger i = 0; i < valuesRange.length; ++i) {
					if ( valuesRange.location <= SIZE_MAX && i <= SIZE_MAX - valuesRange.location && valuesRange.location + i < numberOfOldValues) {
						isValueUsed[valuesRange.location + i] = YES;
					}
				}
			}

			BOOL hasUnusedValue = NO;
			for (NSUInteger i = 0; i < numberOfOldValues; ++i) {
				if (!isValueUsed[i]) {
					hasUnusedValue = YES;
					break;
				}
			}

			if (hasUnusedValue) {
				NSUInteger * const valueIndexTranslationTable = calloc(sizeof *valueIndexTranslationTable, numberOfOldValues);

				if (valueIndexTranslationTable) {
					for (NSUInteger i = 0, updatedIndex = 0; i < numberOfOldValues; ++i) {
						if (isValueUsed[i]) {
							valueIndexTranslationTable[i] = updatedIndex;
							++updatedIndex;
						}
					}

					// Update objects
					NSMutableArray * const newOjbects = [NSMutableArray arrayWithCapacity:oldObjects.count];
					for (MMNibArchiveObject *object in oldObjects) {
						MMNibArchiveObject *newObject = object;
						MMNibArchiveObject *createdObject = nil;
						NSRange const oldValuesRange = object.valuesRange;
						NSUInteger const newValuesRangeLocation = valueIndexTranslationTable[oldValuesRange.location];
						if (oldValuesRange.location != newValuesRangeLocation) {
							NSUInteger const classNameIndex = object.classNameIndex;
							newObject = createdObject = [[MMNibArchiveObject alloc] initWithClassNameIndex:classNameIndex valuesRange:NSMakeRange(newValuesRangeLocation, oldValuesRange.length)];
						}
						[newOjbects addObject:newObject];
						MM_release(createdObject);
					}

					// Remove values
					NSMutableArray * const newValues = [NSMutableArray arrayWithCapacity:numberOfOldValues];
					for (NSUInteger i = 0; i < numberOfOldValues; ++i) {
						if (isValueUsed[i]) {
							[newValues addObject:[oldValues objectAtIndex:i]];
						}
					}

					NSError *error = nil;
					MMNibArchive *strippedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:newOjbects keys:archive.keys values:newValues classNames:archive.classNames error:&error]);
					if (strippedArchive) {
						result = strippedArchive;
					}

					free(valueIndexTranslationTable);
				}
			}

			free(isValueUsed);
		}
	}

	return result;
}


