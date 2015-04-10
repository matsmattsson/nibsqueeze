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

#ifndef header_guard_MMMacros_h
#define header_guard_MMMacros_h

#define ARRAY_ELEMENT_COUNT( a__ ) (sizeof(a__) / sizeof((a__)[0]))

#if __clang__
#define MM_UNUSED __attribute__((unused))
#endif

#if __OBJC__

#if __has_feature(objc_arc)
#define MM_release( o_ ) (void)0
#define MM_retain( o_ ) (o_)
#define MM_autorelease( o_ ) o_
#define MM_super_dealloc (void)0
#else /* __has_feature(objc_arc) */
#define MM_release( o_ ) [(o_) release]
#define MM_retain( o_ ) [(o_) retain]
#define MM_autorelease( o_ ) [(o_) autorelease]
#define MM_super_dealloc [super dealloc]
#endif /* __has_feature(objc_arc) */


#endif /* __OBJC__ */

#ifndef MM_UNUSED
#define MM_UNUSED
#endif

#endif
