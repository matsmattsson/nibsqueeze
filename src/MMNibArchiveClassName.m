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

#import "MMNibArchiveClassName.h"

#import "MMMacros.h"

@implementation MMNibArchiveClassName
@synthesize name = m_name;
@synthesize integers = m_integers;
@synthesize nameString = m_nameString;

- (void)dealloc {
	MM_release(m_name);
	MM_release(m_nameString);
	MM_release(m_integers);
	MM_super_dealloc;
}

- (instancetype)initWithName:(NSData *)name integers:(NSArray *)integers {
	self = [super init];
	if (self) {
		m_name = [name copy];
		m_integers = [integers copy];
	}
	return self;
}

- (instancetype)copyWithZone:(NSZone * MM_UNUSED)zone {
	return [[[self class] alloc] initWithName:m_name integers:m_integers];
}

- (BOOL)isEqual:(id)object {
	BOOL isEqual = [super isEqual:object];
	if (!isEqual && [object isKindOfClass:[MMNibArchiveClassName class]]) {
		MMNibArchiveClassName *other = object;
		isEqual = [other.name isEqual:self.name] && (other.integers == self.integers || [other.integers isEqual:self.integers]);
	}
	return isEqual;
}

- (NSUInteger)hash {
	return [m_name hash] ^ [m_integers hash];
}


- (NSString *)nameString {
	if (!m_nameString && m_name) {
//		m_nameString = [[NSString alloc] initWithData:self.name encoding:NSUTF8StringEncoding];
		m_nameString = [[NSString alloc] initWithCString:[m_name bytes] encoding:NSUTF8StringEncoding];
	}
	return m_nameString;
}

#ifndef NDEBUG
- (NSString *)debugDescription {
	return [NSString stringWithFormat:@"<%@ %p, name=%@>", NSStringFromClass([self class]), self, self.nameString];
}
#endif

@end
