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

#import "MMNibArchiveObject.h"

#import "MMMacros.h"

@implementation MMNibArchiveObject
@synthesize classNameIndex = m_classNameIndex;
@synthesize valuesRange = m_valuesRange;


- (instancetype)initWithClassNameIndex:(NSUInteger)classNameIndex valuesRange:(NSRange)valuesRange {
	self = [super init];
	if (self) {
		m_classNameIndex = classNameIndex;
		m_valuesRange = valuesRange;
	}
	return self;
}

- (instancetype)copyWithZone:(NSZone *)zone {
	return [[[self class] allocWithZone:zone] initWithClassNameIndex:m_classNameIndex valuesRange:m_valuesRange];
}

- (BOOL)isEqual:(id)object {
	BOOL isEqual = [super isEqual:object];
	if (!isEqual && [object isKindOfClass:[MMNibArchiveObject class]]) {
		MMNibArchiveObject *other = object;
		isEqual = (other.classNameIndex == self.classNameIndex) && NSEqualRanges(other.valuesRange, self.valuesRange);
	}
	return isEqual;
}

- (NSUInteger)hash {
	return 31 * (31 * m_valuesRange.location + m_valuesRange.length) + m_classNameIndex;
}


#ifndef NDEBUG
- (NSString *)debugDescription {
	return [NSString stringWithFormat:@"<%@ %p, class=%jd, values=%@>", NSStringFromClass([self class]), self, (intmax_t)m_classNameIndex, NSStringFromRange(m_valuesRange)];
}
#endif

@end
