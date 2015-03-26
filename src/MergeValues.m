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

#import "MergeValues.h"

#import "DeduplicateValueInstances.h"
#import "MMMacros.h"

static const char *EmptyKeys[] = {
	"NSInlinedValue",
	"UINibEncoderEmptyKey",
};

NSArray *ObjectValueSets(MMNibArchive *archive) {
	NSMutableArray *valueSets = [NSMutableArray arrayWithCapacity:archive.objects.count];

	NSMutableSet *emptyKeys = [NSMutableSet set];
	for (size_t i = 0; i < sizeof(EmptyKeys)/sizeof(EmptyKeys[0]); ++i) {
		NSData *key = [NSData dataWithBytes:EmptyKeys[i] length:strlen(EmptyKeys[i])];
		[emptyKeys addObject:key];
	}

	NSArray * const values = archive.values;
	NSArray * const keys = archive.keys;
	for (MMNibArchiveObject *object in archive.objects) {
		NSMutableSet *valuesSet = [NSMutableSet set];
		NSRange const valuesRange = object.valuesRange;
		NSUInteger const maxIndex = (NSUIntegerMax - valuesRange.length >= valuesRange.location) ? (valuesRange.location + valuesRange.length) : NSUIntegerMax;
		for (NSUInteger i = valuesRange.location; i < maxIndex; ++i) {
			MMNibArchiveValue *value = [values objectAtIndex:i];
			NSData *key = [keys objectAtIndex:value.keyIndex];
			if ([emptyKeys containsObject:key] || [valuesSet containsObject:value]) {
				[valuesSet removeAllObjects];
				break;
			} else {
				[valuesSet addObject:value];
			}
		}

		[valueSets addObject:valuesSet];
	}

	return valueSets;
}

NSUInteger NumberOfObjectsInIntersection(NSSet *setA, NSSet *setB) {
	if (setA.count > setB.count) {
		NSSet *t = setA;
		setA = setB;
		setB = t;
	}

	NSUInteger count = 0;
	for (NSObject *oA in setA) {
		if ([setB containsObject:oA]) {
			++count;
		}
	}
	return count;
}

static int CompareNSUIntegers(const void *aPtr, const void *bPtr) {
	NSUInteger const *nA = aPtr;
	NSUInteger const *nB = bPtr;
	NSUInteger const a = *nA;
	NSUInteger const b = *nB;
	int result = 0;
	if (a < b) {
		result = -1;
	} else if (a > b) {
		result = 1;
	} else if (a == b) {
		result = 0;
	}
	return result;
}

static void SortNSUIntegers(NSUInteger *numbers, size_t count) {
	qsort(numbers, count, sizeof(*numbers), CompareNSUIntegers);
}

static BOOL PermutationStep(NSUInteger *numbers, size_t count) {
	BOOL hasMoreSteps = NO;

	for (size_t i = 0; 1 < count && i < (count - 1); ++i) {
		size_t const keyCandidateIndex = count - 2 - i;
		NSUInteger const keyCandidate = numbers[keyCandidateIndex];
		if (keyCandidate < numbers[keyCandidateIndex + 1]) {
			size_t const keyIndex = keyCandidateIndex;
			NSUInteger const key = keyCandidate;

			size_t swapIndex = keyIndex + 1;
			NSUInteger swap = numbers[swapIndex];
			for (size_t j = keyIndex + 2; j < count; ++j) {
				NSUInteger const v = numbers[j];
				if (key < v && swap > v) {
					swap = v;
					swapIndex = j;
				}
			}

			numbers[keyIndex] = swap;
			numbers[swapIndex] = key;
			SortNSUIntegers(numbers + (keyIndex + 1), count - (keyIndex + 1));
			hasMoreSteps = YES;
			break;
		}
	}

	return hasMoreSteps;
}

static void FindValueCodingForObjectsAtIndexes(const NSUInteger * const indexPermutation, const NSUInteger numberOfObjectsInCluster, NSUInteger * const indexScratchArea, NSUInteger * const indexTranslationTable, NSArray * const valueSets, NSArray * const oldObjects, const NSUInteger objectsIndexOffset, const NSUInteger valuesIndexOffset, NSArray **objectsForShortestValueCoding_p, NSArray ** shortestValueCodingForCluster_p) {
	NSMutableArray *orderedSetsOfValues = [[NSMutableArray alloc] init];
	
	for (size_t i = 0; i < numberOfObjectsInCluster; ++i) {
		NSUInteger const objectIndex = indexPermutation[i];
		NSMutableSet *objectValues = [[NSMutableSet alloc] initWithSet:[valueSets objectAtIndex:objectIndex]];
		
		NSUInteger const numberOfOrderedSetsOfValues = orderedSetsOfValues.count;
		NSUInteger objectCodingStartIndex = numberOfOrderedSetsOfValues;
		for (NSUInteger setIndex = 0; setIndex < numberOfOrderedSetsOfValues; ++setIndex) {
			NSUInteger const index = numberOfOrderedSetsOfValues - 1 - setIndex;
			NSSet * const splitValues = [orderedSetsOfValues objectAtIndex:index];
			NSUInteger const numberOfObjectsInIntersection = NumberOfObjectsInIntersection(splitValues, objectValues);
			if ( 0 < numberOfObjectsInIntersection) {
				if (splitValues.count == numberOfObjectsInIntersection) {
					[objectValues minusSet:splitValues];
					--objectCodingStartIndex;
				} else {
					NSMutableSet *splitValuesA = [[NSMutableSet alloc] initWithCapacity:splitValues.count - numberOfObjectsInIntersection];
					NSMutableSet *splitValuesB = [[NSMutableSet alloc] initWithCapacity:numberOfObjectsInIntersection];
					for (NSObject *value in splitValues) {
						if ([objectValues containsObject:value]) {
							[splitValuesB addObject:value];
						} else {
							[splitValuesA addObject:value];
						}
					}
					
					[orderedSetsOfValues replaceObjectAtIndex:index withObject:splitValuesA];
					[orderedSetsOfValues insertObject:splitValuesB atIndex:index + 1];
					[objectValues minusSet:splitValuesB];
					
					for (size_t j = 0; j < i; ++j) {
						NSUInteger const t = indexScratchArea[j];
						if (t >= objectCodingStartIndex) {
							indexScratchArea[j] = t + 1;
						}
					}

					MM_release(splitValuesA);
					MM_release(splitValuesB);
					break;
				}
			} else {
				break;
			}
		}
		
		[orderedSetsOfValues addObject:objectValues];
		indexScratchArea[i] = objectCodingStartIndex;
		MM_release(objectValues);
	}
	
	NSUInteger numberOfBytesForCodedValues = 0;
	NSUInteger numberOfCodedValues = 0;
	for (NSSet * set in orderedSetsOfValues) {
		numberOfCodedValues += set.count;
		for (MMNibArchiveValue *value in set) {
			NSData *data = value.data;
			if (data) {
				numberOfBytesForCodedValues += [data length];
			}
		}
	}

	NSUInteger numberOfBytesInShortestValuesCodingForCluster = 0;
	if (*shortestValueCodingForCluster_p) {
		for (MMNibArchiveValue *value in *shortestValueCodingForCluster_p) {
			NSData *data = value.data;
			if (data) {
				numberOfBytesInShortestValuesCodingForCluster += [data length];
			}
		}
	}

	if (nil == *shortestValueCodingForCluster_p || numberOfBytesForCodedValues < numberOfBytesInShortestValuesCodingForCluster) {
		NSMutableArray *valueCodingForCluster = [NSMutableArray arrayWithCapacity:numberOfCodedValues];
		NSMutableArray *objectsForCluster = [NSMutableArray arrayWithCapacity:numberOfObjectsInCluster];
		
		for (size_t i = 0; i < numberOfObjectsInCluster; ++i) {
			NSUInteger const objectIndex = indexPermutation[i];
			MMNibArchiveObject * const oldObject = [oldObjects objectAtIndex:objectIndex];
			NSUInteger objectValuesStartOffset = valuesIndexOffset;
			for (NSUInteger j = 0; j < indexScratchArea[i]; ++j) {
				objectValuesStartOffset += [[orderedSetsOfValues objectAtIndex:j] count];
			}

			NSRange const newValuesRange = NSMakeRange(objectValuesStartOffset, oldObject.valuesRange.length);
			MMNibArchiveObject * const newObject = [[MMNibArchiveObject alloc] initWithClassNameIndex:oldObject.classNameIndex valuesRange:newValuesRange];
			NSUInteger const newObjectIndex = objectsIndexOffset + objectsForCluster.count;
			
			[objectsForCluster addObject:newObject];
			indexTranslationTable[objectIndex] = newObjectIndex;
			MM_release(newObject);
		}
		
		for (NSSet *valuesSet in orderedSetsOfValues) {
			[valueCodingForCluster addObjectsFromArray:[valuesSet allObjects]];
		}
		MM_release(*shortestValueCodingForCluster_p);
		MM_release(*objectsForShortestValueCoding_p);
		*shortestValueCodingForCluster_p = MM_retain(valueCodingForCluster);
		*objectsForShortestValueCoding_p = MM_retain(objectsForCluster);
	}

	MM_release(orderedSetsOfValues);
}

void FindGoodClusterOrderingByHeuristic1(NSSet *const cluster, NSUInteger const numberOfObjectsInCluster, NSUInteger const *intersectionCount, NSUInteger const numberOfObjects, NSUInteger *indexPermutation) {
	NSUInteger i = 0;
	for (NSNumber *number in cluster) {
		indexPermutation[i] = [number unsignedIntegerValue];
		++i;
	}

	NSUInteger maxIntersectionCount = 0;
	NSUInteger maxIndexA = 0;
	NSUInteger maxIndexB = 0;
	for (NSUInteger i = 0; i < numberOfObjectsInCluster; ++i) {
		NSUInteger const indexA = indexPermutation[i];
		for (NSUInteger j = i + 1; j < numberOfObjectsInCluster; ++j) {
			NSUInteger const indexB = indexPermutation[j];
			NSUInteger const c = intersectionCount[indexA * numberOfObjects + indexB];
			if (c > maxIntersectionCount) {
				maxIndexA = indexA;
				maxIndexB = indexB;
				maxIntersectionCount = c;
			}
		}
	}
	NSCAssert(maxIndexA != maxIndexB, @"");
	NSMutableArray *indexArray = [NSMutableArray arrayWithCapacity:numberOfObjectsInCluster];
	NSMutableSet *unusedClusterIndexes = [cluster mutableCopy];
	[indexArray addObject:@(maxIndexA)];
	[indexArray addObject:@(maxIndexB)];
	[unusedClusterIndexes removeObject:@(maxIndexA)];
	[unusedClusterIndexes removeObject:@(maxIndexB)];

	while (0 < unusedClusterIndexes.count) {
		NSUInteger const frontIndex = [[indexArray objectAtIndex:0] unsignedIntegerValue];
		NSNumber *maxFrontIndexIntersectionIndex = [unusedClusterIndexes anyObject];
		NSUInteger maxFrontIndexIntersection = 0;
		for (NSNumber *number in unusedClusterIndexes) {
			NSUInteger const i = [number unsignedIntegerValue];
			NSUInteger const c = intersectionCount[frontIndex	* numberOfObjects + i];
			if (c > maxFrontIndexIntersection) {
				maxFrontIndexIntersectionIndex = number;
				maxFrontIndexIntersection = c;
			}
		}

		NSUInteger const backIndex = [[indexArray lastObject] unsignedIntegerValue];
		NSNumber *maxBackIndexIntersectionIndex = [unusedClusterIndexes anyObject];
		NSUInteger maxBackIndexIntersection = 0;
		for (NSNumber *number in unusedClusterIndexes) {
			NSUInteger const i = [number unsignedIntegerValue];
			NSUInteger const c = intersectionCount[backIndex	* numberOfObjects + i];
			if (c > maxBackIndexIntersection) {
				maxBackIndexIntersectionIndex = number;
				maxBackIndexIntersection = c;
			}
		}

		if (maxFrontIndexIntersection > maxBackIndexIntersection) {
			[indexArray insertObject:maxFrontIndexIntersectionIndex atIndex:0];
			[unusedClusterIndexes removeObject:maxFrontIndexIntersectionIndex];
		} else {
			[indexArray addObject:maxBackIndexIntersectionIndex];
			[unusedClusterIndexes removeObject:maxBackIndexIntersectionIndex];
		}
	}

	NSCAssert([cluster isEqual:[NSSet setWithArray:indexArray]], @"");
	NSCAssert(numberOfObjectsInCluster == indexArray.count, @"");


	for (NSUInteger i = 0; i < numberOfObjectsInCluster; ++i) {
		indexPermutation[i] = [[indexArray objectAtIndex:i] unsignedIntegerValue];
	}
}

MMNibArchive * MergeValues(MMNibArchive *archive) {
	MMNibArchive *result = DeduplicateValueInstances(archive);

	NSArray * const valueSets = ObjectValueSets(result);
	NSArray * const oldObjects = result.objects;
	NSArray * const oldValues = result.values;
	NSUInteger const numberOfObjects = oldObjects.count;

	if (SIZE_MAX / numberOfObjects > numberOfObjects ) {
		NSUInteger *intersectionCount = calloc(sizeof *intersectionCount, numberOfObjects * numberOfObjects);
		if (intersectionCount) {

			for (NSUInteger i = 0; i < numberOfObjects; ++i) {
				NSSet *setA = [valueSets objectAtIndex:i];
				intersectionCount[i * numberOfObjects + i] = setA.count;
				for (NSUInteger j = 0; j < i; ++j) {
					NSSet *setB = [valueSets objectAtIndex:j];
					NSUInteger const c = NumberOfObjectsInIntersection(setA, setB);
					if (0 < c) {
						intersectionCount[i * numberOfObjects + j] = c;
						intersectionCount[j * numberOfObjects + i] = c;
					}
				}
			}

			NSMutableArray *objectIntersectionClusters = [NSMutableArray array];
			NSUInteger numberOfObjectsInLargestCluster = 1;
			{
				NSMutableSet *uncheckedObjectIndexes = [NSMutableSet setWithCapacity:numberOfObjects];
				for (NSUInteger i = 0; i < numberOfObjects; ++i) {
					[uncheckedObjectIndexes addObject:@(i)];
				}

				while (0 < uncheckedObjectIndexes.count) {
					NSNumber *objectIndex = [uncheckedObjectIndexes anyObject];
					NSMutableSet *workSet = [NSMutableSet setWithObject:objectIndex];
					[uncheckedObjectIndexes removeObject:objectIndex];
					NSMutableSet *cluster = [NSMutableSet set];
					while (0 < workSet.count) {
						NSNumber *n = [workSet anyObject];
						[cluster addObject:n];
						[workSet removeObject:n];
						NSUInteger nValue = [n unsignedIntegerValue];
						for (NSUInteger i = 0; i < numberOfObjects; ++i) {
							if (i != nValue) {
								NSUInteger const c = intersectionCount[nValue * numberOfObjects + i];
								if (0 != c) {
									NSNumber *iNumber = @(i);
									if ([uncheckedObjectIndexes containsObject:iNumber]) {
										[uncheckedObjectIndexes removeObject:iNumber];
										[workSet addObject:iNumber];
									}
								}
							}
						}
					}

					[objectIntersectionClusters addObject:cluster];
					NSUInteger const numberOfObjectsInCluster = cluster.count;
					if (numberOfObjectsInLargestCluster < numberOfObjectsInCluster ) {
						numberOfObjectsInLargestCluster = numberOfObjectsInCluster;
					}
				}
			}
			NSUInteger *indexPermutation = calloc(sizeof *indexPermutation, numberOfObjectsInLargestCluster);
			NSUInteger *indexScratchArea = calloc(sizeof *indexScratchArea, numberOfObjectsInLargestCluster);
			NSUInteger *indexTranslationTable = calloc(sizeof *indexScratchArea, numberOfObjects);

			if (indexPermutation && indexScratchArea && indexTranslationTable) {
				NSMutableArray *newObjects = [NSMutableArray array];
				NSMutableArray *newValues = [NSMutableArray array];

				for (NSSet *cluster in objectIntersectionClusters) {
					NSUInteger const valuesIndexOffset = newValues.count;
					NSUInteger const objectsIndexOffset = newObjects.count;
					NSUInteger const numberOfObjectsInCluster = cluster.count;

					if ( 0 >= numberOfObjectsInCluster) {
						NSCAssert(false,NULL);
					} else if ( 1 == numberOfObjectsInCluster) {
						NSUInteger const oldObjectIndex = [[cluster anyObject] unsignedIntegerValue];
						MMNibArchiveObject *oldObject = [oldObjects objectAtIndex:oldObjectIndex];
						NSArray *values = [oldValues subarrayWithRange:oldObject.valuesRange];
						MMNibArchiveObject *object = [[MMNibArchiveObject alloc] initWithClassNameIndex:oldObject.classNameIndex valuesRange:NSMakeRange(valuesIndexOffset, values.count)];
						NSUInteger const newObjectIndex = objectsIndexOffset;
						indexTranslationTable[oldObjectIndex] = newObjectIndex;
						[newObjects addObject:object];
						[newValues addObjectsFromArray:values];
						MM_release(object);
					} else if (numberOfObjectsInCluster < 8) {
						{
							NSUInteger i = 0;
							for (NSNumber *number in cluster) {
								indexPermutation[i] = [number unsignedIntegerValue];
								++i;
							}
						}
						SortNSUIntegers(indexPermutation, numberOfObjectsInCluster);

						NSArray *shortestValueCodingForCluster = nil;
						NSArray *objectsForShortestValueCoding = nil;

						do {
							@autoreleasepool {
								FindValueCodingForObjectsAtIndexes(indexPermutation, numberOfObjectsInCluster, indexScratchArea, indexTranslationTable, valueSets, oldObjects, objectsIndexOffset, valuesIndexOffset, &objectsForShortestValueCoding, &shortestValueCodingForCluster);
							}
						} while (PermutationStep(indexPermutation, numberOfObjectsInCluster));

						[newObjects addObjectsFromArray:objectsForShortestValueCoding];
						[newValues addObjectsFromArray:shortestValueCodingForCluster];
						MM_release(objectsForShortestValueCoding);
						MM_release(shortestValueCodingForCluster);
					} else {
						{
							NSUInteger i = 0;
							for (NSNumber *number in cluster) {
								indexPermutation[i] = [number unsignedIntegerValue];
								++i;
							}
						}
						SortNSUIntegers(indexPermutation, numberOfObjectsInCluster);

						NSArray *shortestValueCodingForCluster = nil;
						NSArray *objectsForShortestValueCoding = nil;

						@autoreleasepool {
							FindValueCodingForObjectsAtIndexes(indexPermutation, numberOfObjectsInCluster, indexScratchArea, indexTranslationTable, valueSets, oldObjects, objectsIndexOffset, valuesIndexOffset, &objectsForShortestValueCoding, &shortestValueCodingForCluster);
						}
						
						@autoreleasepool {
							FindGoodClusterOrderingByHeuristic1(cluster, numberOfObjectsInCluster, intersectionCount, numberOfObjects, indexPermutation);
							FindValueCodingForObjectsAtIndexes(indexPermutation, numberOfObjectsInCluster, indexScratchArea, indexTranslationTable, valueSets, oldObjects, objectsIndexOffset, valuesIndexOffset, &objectsForShortestValueCoding, &shortestValueCodingForCluster);
						}

						[newObjects addObjectsFromArray:objectsForShortestValueCoding];
						[newValues addObjectsFromArray:shortestValueCodingForCluster];
						MM_release(objectsForShortestValueCoding);
						MM_release(shortestValueCodingForCluster);
					}
				}

				NSUInteger const numberOfNewValues = newValues.count;
				for (NSUInteger i = 0; i < numberOfNewValues; ++i) {
					MMNibArchiveValue *value = [newValues objectAtIndex:i];
					if (kMMNibArchiveValueTypeObjectReference == value.type) {
						uint32_t const oldObjectIndex = value.objectReference;
						if (oldObjectIndex < numberOfObjects) {
							NSUInteger newObjectIndex = indexTranslationTable[oldObjectIndex];
							if (oldObjectIndex != newObjectIndex && newObjectIndex <= UINT32_MAX) {
								MMNibArchiveValue *newValue = [[MMNibArchiveValue alloc] initWithObjectReference:(uint32_t)newObjectIndex forKeyIndex:value.keyIndex];
								[newValues replaceObjectAtIndex:i withObject:newValue];
								MM_release(newValue);
							}
						}
					}
				}

				NSCAssert(newObjects.count == oldObjects.count, nil);
#ifndef NDEBUG
				for (NSUInteger oldObjectIndex = 0; oldObjectIndex < numberOfObjects; ++oldObjectIndex) {
					NSUInteger newObjectIndex = indexTranslationTable[oldObjectIndex];
					MMNibArchiveObject *oldObject = [oldObjects objectAtIndex:oldObjectIndex];
					MMNibArchiveObject *newObject = [newObjects objectAtIndex:newObjectIndex];
					NSRange const oldRange = oldObject.valuesRange;
					NSRange const newRange = newObject.valuesRange;
					NSCAssert(oldRange.length == newRange.length, @"");
					NSSet *oldObjectValues = [NSSet setWithArray:[oldValues subarrayWithRange:oldRange]];
					NSSet *newObjectValues = [NSSet setWithArray:[newValues subarrayWithRange:newRange]];
					NSCAssert(oldObjectValues.count == newObjectValues.count, @"");
					for (MMNibArchiveValue *value in oldObjectValues) {
						if (value.type != kMMNibArchiveValueTypeObjectReference) {
							NSCAssert([newObjectValues containsObject:value], @"");
						}
					}
				}
#endif

				if (newValues.count < oldValues.count) {
					NSError *error = nil;
					MMNibArchive *mergedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:newObjects keys:result.keys values:newValues classNames:result.classNames error:&error]);
					NSCAssert(mergedArchive, @"%@", error);
					if (mergedArchive) {
						result = mergedArchive;
					}
				}
			}

			if (indexPermutation) {
				free(indexPermutation);
				indexPermutation = NULL;
			}

			if (indexScratchArea) {
				free(indexScratchArea);
				indexScratchArea = NULL;
			}

			if (indexTranslationTable) {
				free(indexTranslationTable);
				indexTranslationTable = NULL;
			}


			free(intersectionCount);
		}
	}


	return result;
}