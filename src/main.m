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

#import <Foundation/Foundation.h>

#import <getopt.h>
#import <string.h>
#import <sys/ioctl.h>

#import "MMNibArchive.h"
#import "MMMacros.h"
#import "DeduplicateConstantObjects.h"
#import "DeduplicateValueInstances.h"
#import "MergeEqualObjects.h"
#import "MergeValues.h"
#import "StripUnusedClassNames.h"
#import "StripUnusedValues.h"

#define TOOL_NAME "nibsqueeze"
#define TOOL_NAME_UPPERCASE "NIBSQUEEZE"

#define ENV_PREFIX TOOL_NAME_UPPERCASE "_"
#define ENV_VALUE_YES "YES"
#define ENV_VALUE_NO "NO"

#define PRINT_ERROR_PREFIX TOOL_NAME ": error: "
#define PRINT_WARNING_PREFIX TOOL_NAME ": warning: "
#define PRINT_DEBUG_PREFIX TOOL_NAME ": debug: "

#define VERSION_STRING TOOL_NAME " 1.0, (C) 2015 Mats Mattsson"

#define NIB_FILE_EXTENSION_LOWER @"nib"



@interface MMNibDataContainer : NSObject
@property (strong) NSString *path;
@property (strong) NSData *originalData;
@property (strong) NSData *updatedData;
@end

enum OptionValue {
	kOptionUnset = 0,
	kOptionEnabled = 1,
	kOptionDisabled = 2,
};

enum OptionIndex {
	kOptionEverything,
	kOptionDeduplicateConstantObjects,
	kOptionMergeEqualObjects,
	kOptionMergeValues,
	kOptionStripUnusedClassNames,
	kOptionStripUnusedValues,
	kOptionParseEnvironment,
	kOptionParseXcodeEnvironment,
};

enum CommandLineLongOption {
	kCommandLineVerbose = 'v',
	kCommandLineDebug = 'd',
	kCommandLineSilent = 'q',
	kCommandLineHelp = 'h',
	kCommandLineRecursive = 'r',
	kCommandLineOptionUnknown = '?',
	kCommandLineOptionMissingArgument = ':',
	kCommandLineLongOptionLastShortOption = UCHAR_MAX,
	kCommandLineEnable,
	kCommandLineDisable,
	kCommandLineEnableDeduplicateConstantObjects,
	kCommandLineDisableDeduplicateConstantObjects,
	kCommandLineEnableMergeEqualObjects,
	kCommandLineDisableMergeEqualObjects,
	kCommandLineEnableMergeValues,
	kCommandLineDisableMergeValues,
	kCommandLineEnableStripUnusedClassNames,
	kCommandLineDisableStripUnusedClassNames,
	kCommandLineEnableStripUnusedValues,
	kCommandLineDisableStripUnusedValues,
	kCommandLineEnableParseEnvironment,
	kCommandLineDisableParseEnvironment,
	kCommandLineVersion,
};

enum LogLevel {
	kLogLevelSilent,
	kLogLevelDefault,
	kLogLevelVerbose1,
	kLogLevelDebug,
};

static int GlobalLogLevel = kLogLevelDefault;

#define LOG_LEVEL_printf( logLevel__, ...) ((GlobalLogLevel >= (logLevel__)) ? printf(__VA_ARGS__) : 0)
#define LOG_LEVEL_fprintf( logLevel__, ...) ((GlobalLogLevel >= (logLevel__)) ? fprintf(__VA_ARGS__) : 0)

#define LOG_DEBUG_printf( ... ) LOG_LEVEL_printf( kLogLevelDebug, PRINT_DEBUG_PREFIX __VA_ARGS__ )
#define LOG_VERBOSE1_RAW_printf( ... ) LOG_LEVEL_printf( kLogLevelDebug, __VA_ARGS__ )
#define LOG_WARNING_printf( ... ) fprintf(stderr, PRINT_WARNING_PREFIX __VA_ARGS__ )
#define LOG_ERROR_printf( ... ) fprintf(stderr, PRINT_ERROR_PREFIX __VA_ARGS__ )

static MMNibArchive *smallerNibArchiveForOptions(MMNibArchive *archive, enum OptionValue const *settings);

enum OptionValue const DefaultOptionValues[] = {
	[kOptionEverything] = kOptionUnset,
	[kOptionDeduplicateConstantObjects] = kOptionEnabled,
	[kOptionMergeEqualObjects] = kOptionDisabled,
	[kOptionMergeValues] = kOptionEnabled,
	[kOptionStripUnusedClassNames] = kOptionEnabled,
	[kOptionStripUnusedValues] = kOptionDisabled,
	[kOptionParseEnvironment] = kOptionEnabled,
	[kOptionParseXcodeEnvironment] = kOptionEnabled,
};

static struct {
	const char *env;
	enum OptionIndex index;
} const EnvironmentNameList[] = {
	{ .env = ENV_PREFIX "ENABLE", .index = kOptionEverything },
	{ .env = ENV_PREFIX "ENABLE_DEDUPLICATE_CONSTANT_OBJECTS", .index = kOptionDeduplicateConstantObjects },
	{ .env = ENV_PREFIX "ENABLE_MERGE_EQUAL_OBJECTS", .index = kOptionMergeEqualObjects},
	{ .env = ENV_PREFIX "ENABLE_MERGE_VALUES", .index = kOptionMergeValues},
	{ .env = ENV_PREFIX "ENABLE_STRIP_UNUSED_VALUES", .index = kOptionStripUnusedValues},
	{ .env = ENV_PREFIX "ENABLE_STRIP_UNUSED_CLASS_NAMES", .index = kOptionStripUnusedClassNames},
};

static struct option const CommandLineOptions[] = {
	{"enable", no_argument, NULL, kCommandLineEnable},
	{"disable", no_argument, NULL, kCommandLineDisable},
	{"enable-deduplicate-constant-objects", no_argument, NULL, kCommandLineEnableDeduplicateConstantObjects},
	{"disable-deduplicate-constant-objects", no_argument, NULL, kCommandLineDisableDeduplicateConstantObjects},
	{"enable-merge-equal-objects", no_argument, NULL, kCommandLineEnableMergeEqualObjects},
	{"disable-merge-equal-objects", no_argument, NULL, kCommandLineDisableMergeEqualObjects},
	{"enable-merge-values", no_argument, NULL, kCommandLineEnableMergeValues},
	{"disable-merge-values", no_argument, NULL, kCommandLineDisableMergeValues},
	{"enable-strip-unused-class-names", no_argument, NULL, kCommandLineEnableStripUnusedClassNames},
	{"disable-strip-unused-class-names", no_argument, NULL, kCommandLineDisableStripUnusedClassNames},
	{"enable-strip-unused-values", no_argument, NULL, kCommandLineEnableStripUnusedValues},
	{"disable-strip-unused-values", no_argument, NULL, kCommandLineDisableStripUnusedValues},
	{"enable-parse-environment", no_argument, NULL, kCommandLineEnableParseEnvironment},
	{"disable-parse-environment", no_argument, NULL, kCommandLineDisableParseEnvironment},
	{"verbose", no_argument, NULL, kCommandLineVerbose},
	{"debug", no_argument, NULL, kCommandLineDebug},
	{"silent", no_argument, NULL, kCommandLineSilent},
	{"recursive", no_argument, NULL, kCommandLineRecursive},
	{"version", no_argument, NULL, kCommandLineVersion},
	{"help", no_argument, NULL, kCommandLineHelp},
	{NULL, 0, NULL, 0},
};

static const char * CommandLineOptionsHelp[] = {
	[kCommandLineVersion] = "Print the software version number.",
	[kCommandLineHelp] = "Print this help text.",
	[kCommandLineDebug] = "Enable debug prints.",
	[kCommandLineVerbose] = "Increase the printed output.",
	[kCommandLineSilent] = "Disable all logging, except error messages.",
	[kCommandLineEnable] = "Enable processing of nib files.",
	[kCommandLineDisable] = "Disable processing of nib files.",
	[kCommandLineEnableDeduplicateConstantObjects] = "Replace equally coded objects of a list of nonmutable types by one object.",
	[kCommandLineDisableDeduplicateConstantObjects] = "Disable the pass that will deduplicate nonmutable obects.",
	[kCommandLineEnableMergeEqualObjects] = "Set objects that are equally coded to use the same stored data.",
	[kCommandLineDisableMergeEqualObjects] = "Disable the pass that will set equally coded objects to share data.",
	[kCommandLineEnableMergeValues] = "Make an effort to make objects with some equally coded values to share those values in the stored data.",
	[kCommandLineDisableMergeValues] = "Disable the pass that make objects with some equally coded values to share those values in the stored data.",
	[kCommandLineEnableStripUnusedValues] = "Remove items in the values list that are not referenced by any object.",
	[kCommandLineDisableStripUnusedValues] = "Disable the pass that removes items in the values list that are not referenced by any object.",
	[kCommandLineEnableStripUnusedClassNames] = "Remove items in the class names list that are not referenced by any object.",
	[kCommandLineDisableStripUnusedClassNames] = "Disable the pass that removes items in the class names list that are not referenced by any object.",
	[kCommandLineEnableParseEnvironment] = "Enable using environment variables to controll the behavior of " TOOL_NAME ".",
	[kCommandLineDisableParseEnvironment] = "Disable using environment variables to controll the behavior of " TOOL_NAME ".",
	[kCommandLineRecursive] = "Search input files recursively.",
};

static const char * EnvironmentHelp = ""
"Set the following environment variables to either " ENV_VALUE_YES
" or " ENV_VALUE_NO " to enable or disable the respective functionality."
"";

static const char * EnvironmentOptionsHelp[] = {
	[kOptionEverything] = "If set to " ENV_VALUE_NO ", it will disable all operations.",
	[kOptionDeduplicateConstantObjects] = "Replace equally coded objects of a list of nonmutable types by one object.",
	[kOptionMergeEqualObjects] = "Set objects that are equally coded to use the same stored data.",
	[kOptionMergeValues] = "Make an effort to make objects with some equally coded values to share those values in the stored data.",
	[kOptionStripUnusedValues] = "Remove items in the values list that are not referenced by any object.",
	[kOptionStripUnusedClassNames] = "Remove items in the class names list that are not referenced by any object.",
};

static int xcodeBuildSupportsNibArchiveFiles(void) {
	int r = 0;
	static const char * iphoneosDeploymentTargetEnvironmentName = "IPHONEOS_DEPLOYMENT_TARGET";
	const char * iphoneosDeploymentTargetUTF8String = getenv(iphoneosDeploymentTargetEnvironmentName);
	if (iphoneosDeploymentTargetUTF8String) {
		NSString * iphoneosDeploymentTarget = [[NSString alloc] initWithUTF8String:iphoneosDeploymentTargetUTF8String];
		if (NSOrderedDescending != [@"6" compare:iphoneosDeploymentTarget options:NSNumericSearch]) {
			r = 1;
		} else {
			LOG_WARNING_printf("No support for iOS versions prior to 6.0. (%s=%s)\n", iphoneosDeploymentTargetEnvironmentName, iphoneosDeploymentTargetUTF8String);
		}
		MM_release(iphoneosDeploymentTarget);
	} else {
		LOG_WARNING_printf("Xcode build environment has not set IPHONEOS_DEPLOYMENT_TARGET.\n");
	}

	return r;
}

static void mergeOptions(enum OptionValue const oldValues[], enum OptionValue const newValues[], enum OptionValue result[], size_t const numberOfOptions) {
	for (size_t i = 0; i < numberOfOptions; ++i) {
		enum OptionValue value = oldValues[i];
		enum OptionValue const newValue = newValues[i];
		if (newValue != kOptionUnset) {
			value = newValue;
		}
		result[i] = value;
	}
}

static void printHelpText(const char * helpText) {
	size_t maxLineLength = 60;
	struct winsize terminal_size = { 0 };
	if (-1 != ioctl(STDOUT_FILENO, TIOCGWINSZ, &terminal_size)) {
		if (20 <= terminal_size.ws_col) {
			maxLineLength = terminal_size.ws_col - 8;
		}
	}

	size_t const helpTextLength = strlen(helpText);
	for (size_t helpOffset = 0; helpOffset < helpTextLength;) {
		size_t lineLength = helpOffset + maxLineLength < helpTextLength ? maxLineLength : (helpTextLength - helpOffset + 1);
		if (helpOffset + lineLength < helpTextLength) {
			while (0 < lineLength && helpText[helpOffset + lineLength - 1] != ' ') {
				--lineLength;
			}
			if (0 == lineLength) {
				lineLength = maxLineLength;
			}
		}

		fprintf(stdout, "        %.*s\n", (unsigned int)lineLength - 1, helpText + helpOffset);
		helpOffset += lineLength;
	}
}

void writeCompletedNibFiles(dispatch_semaphore_t dispatchSemaphore, NSMutableDictionary *nibFileResults) {
	NSDictionary *nibFileResultsCopy = nil;
	long const semaphore_wait_result = dispatch_semaphore_wait(dispatchSemaphore, DISPATCH_TIME_FOREVER);
	assert(0 == semaphore_wait_result);
	nibFileResultsCopy = [nibFileResults copy];
	[nibFileResults removeAllObjects];
	dispatch_semaphore_signal(dispatchSemaphore);
	
	for (NSString *nibPath in [nibFileResultsCopy keyEnumerator]) {
		MMNibDataContainer *container = [nibFileResultsCopy objectForKey:nibPath];
		if (container.updatedData) {
			NSError *nibWriteError = nil;
			BOOL const writeResult = [container.updatedData writeToFile:nibPath options:NSDataWritingAtomic error:&nibWriteError];
			if (!writeResult) {
				fprintf(stderr, "%s: error: Could not write file: %s\n", [nibPath UTF8String], [[nibWriteError localizedDescription] UTF8String]);
			} else {
				NSUInteger const oldSize = [container.originalData length];
				NSUInteger const newSize = [container.updatedData length];
				LOG_VERBOSE1_RAW_printf("%s: info: Reduced file size %.2f%% (%jd bytes, from %jd to %jd).\n", [nibPath UTF8String], 100 * (1. - (double)newSize / (double)oldSize), oldSize - newSize, oldSize, newSize);
			}
		}
	}
	
	MM_release(nibFileResultsCopy);
}

MMNibArchive *smallerEmbeddedNibArchivesForOptions(MMNibArchive *archive, enum OptionValue const *settings) {
	BOOL hasNibDataKey = NO;
	NSArray *keys = archive.keys;
	NSUInteger const numberOfKeys = keys.count;
	NSUInteger nibDataKeyIndex = 0;

	static const uint8_t nibDataKey[] = {'N', 'S', '.', 'b', 'y', 't', 'e', 's',};
	for (NSUInteger i = 0; i < numberOfKeys; ++i) {
		NSData *key = [keys objectAtIndex:i];
		if (sizeof(nibDataKey) == [key length] && 0 == memcmp(nibDataKey, [key bytes], sizeof(nibDataKey))) {
			hasNibDataKey = YES;
			nibDataKeyIndex = i;
			break;
		}
	}

	if (hasNibDataKey) {
		BOOL hasUpdatedValue = NO;
		NSArray * const oldValues = archive.values;
		NSUInteger const numberOfValues = oldValues.count;
		NSMutableArray *updatedValues = [NSMutableArray arrayWithCapacity:numberOfValues];
		for (NSUInteger i = 0; i < numberOfValues; ++i) {
			MMNibArchiveValue *value = [oldValues objectAtIndex:i];
			if (kMMNibArchiveValueTypeData == value.type && nibDataKeyIndex == value.keyIndex) {
				NSData *data = value.dataValue;
				NSError *error = nil;
				MMNibArchive *embeddedNib = [[MMNibArchive alloc] initWithData:data error:&error];
				if (embeddedNib) {
					embeddedNib = smallerNibArchiveForOptions(embeddedNib, settings);

					if (embeddedNib.data && [embeddedNib.data length] < [data length]) {
						hasUpdatedValue = YES;
						MMNibArchiveValue *newValue = MM_autorelease([[MMNibArchiveValue alloc] initWithDataValue:embeddedNib.data forKeyIndex:nibDataKeyIndex]);
						if (newValue) {
							value = newValue;
						}
					}
				}
				MM_release(embeddedNib);
			}
			[updatedValues addObject:value];
		}

		if (hasUpdatedValue) {
			NSError *error = nil;
			MMNibArchive *updatedArchive = MM_autorelease([[MMNibArchive alloc] initWithObjects:archive.objects keys:archive.keys values:updatedValues classNames:archive.classNames error:&error]);
			if (updatedArchive) {
				archive = updatedArchive;
			}
		}
	}

	return archive;
}

static MMNibArchive *smallerNibArchiveForOptions(MMNibArchive *archive, enum OptionValue const *settings) {
	if (archive) {
		archive = DeduplicateValueInstances(archive);
	}

	if (archive) {
		archive = smallerEmbeddedNibArchivesForOptions(archive, settings);
	}

	if (archive && settings[kOptionDeduplicateConstantObjects] == kOptionEnabled) {
		archive = DeduplicateConstantObjects(archive);
	}
	
	if (archive && settings[kOptionMergeEqualObjects] == kOptionEnabled) {
		archive = MergeEqualObjects(archive);
	}
	
	if (archive && settings[kOptionMergeValues] == kOptionEnabled) {
		archive = MergeValues(archive);
	}
	
	if (archive && settings[kOptionStripUnusedClassNames] == kOptionEnabled) {
		archive = StripUnusedClassNames(archive);
	}
	
	if (archive && settings[kOptionStripUnusedValues] == kOptionEnabled) {
		archive = StripUnusedValues(archive);
	}

	return archive;
}

int main(int argc, char **argv) {
	int e = 0;
	enum OptionValue options[ARRAY_ELEMENT_COUNT(DefaultOptionValues)] = { 0 };
	enum OptionValue commandLineOptions[ARRAY_ELEMENT_COUNT(options)] = { 0 };
	enum OptionValue environmentOptions[ARRAY_ELEMENT_COUNT(options)] = { 0 };

	int printVersion = 0;
	int printHelp = 0;
	int recursive = 0;

	// Parse command line

	for (int value = 0, longindex = 0; (value = getopt_long(argc, argv, ":?dhqrv", CommandLineOptions, &longindex)) != -1;) {
		switch((enum CommandLineLongOption)value) {
			case kCommandLineLongOptionLastShortOption:
				break;
			case kCommandLineOptionMissingArgument:
				printHelp = 1;
				e = 1;
				break;
			case kCommandLineOptionUnknown:
				printHelp = 1;
				e = 1;
				break;
			case kCommandLineEnableDeduplicateConstantObjects:
				commandLineOptions[kOptionDeduplicateConstantObjects] = kOptionEnabled;
				break;
			case kCommandLineDisableDeduplicateConstantObjects:
				commandLineOptions[kOptionDeduplicateConstantObjects] = kOptionDisabled;
				break;
			case kCommandLineEnableParseEnvironment:
				commandLineOptions[kOptionParseEnvironment] = kOptionEnabled;
				break;
			case kCommandLineDisableParseEnvironment:
				commandLineOptions[kOptionParseEnvironment] = kOptionDisabled;
				break;
			case kCommandLineEnableMergeEqualObjects:
				commandLineOptions[kOptionMergeEqualObjects] = kOptionEnabled;
				break;
			case kCommandLineDisableMergeEqualObjects:
				commandLineOptions[kOptionMergeEqualObjects] = kOptionDisabled;
				break;
			case kCommandLineEnableMergeValues:
				commandLineOptions[kOptionMergeValues] = kOptionEnabled;
				break;
			case kCommandLineDisableMergeValues:
				commandLineOptions[kOptionMergeValues] = kOptionDisabled;
				break;
			case kCommandLineEnableStripUnusedClassNames:
				commandLineOptions[kOptionStripUnusedClassNames] = kOptionEnabled;
				break;
			case kCommandLineDisableStripUnusedClassNames:
				commandLineOptions[kOptionStripUnusedClassNames] = kOptionDisabled;
				break;
			case kCommandLineEnableStripUnusedValues:
				commandLineOptions[kOptionStripUnusedValues] = kOptionEnabled;
				break;
			case kCommandLineDisableStripUnusedValues:
				commandLineOptions[kOptionStripUnusedValues] = kOptionDisabled;
				break;
			case kCommandLineSilent:
				GlobalLogLevel = kLogLevelSilent;
				break;
			case kCommandLineDebug:
				GlobalLogLevel = kLogLevelDebug;
				break;
			case kCommandLineVerbose:
				GlobalLogLevel = GlobalLogLevel < kLogLevelVerbose1 ? kLogLevelVerbose1 : (GlobalLogLevel < INT_MAX ? (GlobalLogLevel + 1) : INT_MAX);
				break;
			case kCommandLineVersion:
				printVersion = 1;
				break;
			case kCommandLineHelp:
				printHelp = 1;
				break;
			case kCommandLineRecursive:
				recursive = 1;
				break;
			case kCommandLineDisable:
				commandLineOptions[kOptionEnabled] = kOptionDisabled;
				break;
			case kCommandLineEnable:
				commandLineOptions[kOptionEnabled] = kOptionEnabled;
				break;
		}
	}

	if (printVersion || printHelp) {
		fprintf(stdout, "%s\n", VERSION_STRING);
	}

	if (printHelp) {
		fprintf(stdout, "\nCommand line\n");

		for (size_t i = 0; i < ARRAY_ELEMENT_COUNT(CommandLineOptions); ++i) {
			const int helpIndex = CommandLineOptions[i].val;
			const char *helpText = CommandLineOptionsHelp[helpIndex];
			if (helpText) {
				if (helpIndex < CHAR_MAX) {
					fprintf(stdout, "    -%c, --%s\n", helpIndex, CommandLineOptions[i].name);
				} else {
					fprintf(stdout, "    --%s\n", CommandLineOptions[i].name);
				}
				printHelpText(helpText);
			} else {
				if (CommandLineOptions[i].name) {
					LOG_DEBUG_printf("No help for command line option --%s.\n", CommandLineOptions[i].name);
				}
			}
		}
		fprintf(stdout, "\nEnvironment\n");
		printHelpText(EnvironmentHelp);

		for (size_t i = 0; i < ARRAY_ELEMENT_COUNT(EnvironmentNameList); ++i) {
			const char *helpText = EnvironmentOptionsHelp[EnvironmentNameList[i].index];
			if (helpText) {
				fprintf(stdout, "    %s\n", EnvironmentNameList[i].env);
				printHelpText(helpText);
			} else {
				if (EnvironmentNameList[i].env) {
					LOG_DEBUG_printf("No help for environment variable %s.\n", EnvironmentNameList[i].env);
				}
			}
		}

		fprintf(stdout, "\n");
	}

	if (!printHelp && !printVersion) {
		@autoreleasepool {
			NSFileManager * const fileManager = [[NSFileManager alloc] init];

			if (kOptionDisabled != commandLineOptions[kOptionParseEnvironment]) {

				for (size_t i = 0; i < ARRAY_ELEMENT_COUNT(EnvironmentNameList); ++i) {
					const char *value = getenv(EnvironmentNameList[i].env);
					if (value) {
						if (0 == strcmp(ENV_VALUE_YES, value)) {
							environmentOptions[EnvironmentNameList[i].index] = kOptionEnabled;
						} else if (0 == strcmp(ENV_VALUE_NO, value)) {
							environmentOptions[EnvironmentNameList[i].index] = kOptionDisabled;
						} else {
							LOG_WARNING_printf( "Unknown value for environment variable %s. Expected " ENV_VALUE_YES " or " ENV_VALUE_NO ", but was: %s\n", EnvironmentNameList[i].env, value);
						}
					}
				}
			} else {
				LOG_DEBUG_printf("Skipping parsing of environment.\n");
			}

			NSMutableArray *fileList = [NSMutableArray array];
			NSMutableArray *recursiveFileList = [NSMutableArray array];

			for (int i = optind; i < argc; ++i) {
				NSString *arg = [NSString stringWithUTF8String:argv[i]];
				if (recursive) {
					[recursiveFileList addObject:arg];
				} else {
					[fileList addObject:arg];
				}
			}

			if (0 < fileList.count || 0 < recursiveFileList.count) {
				LOG_DEBUG_printf("Skipping parsing of Xcode build environment as there are files on the command line.\n");
			} else if (kOptionDisabled == commandLineOptions[kOptionParseXcodeEnvironment] ) {
				LOG_DEBUG_printf("Skipping parsing of Xcode build environment.\n");
			} else {
				static const char * builtProductsDirEnvironmentName = "BUILT_PRODUCTS_DIR";
				static const char * wrapperNameEnvironmentName = "WRAPPER_NAME";
				const char * builtProductsDirUTF8String = getenv(builtProductsDirEnvironmentName);
				const char * wrapperNameUTF8String = getenv(wrapperNameEnvironmentName);
				if (builtProductsDirUTF8String && wrapperNameUTF8String) {
					NSString *builtProductsDir = [NSString stringWithUTF8String:builtProductsDirUTF8String];
					NSString *wrapperName = [NSString stringWithUTF8String:wrapperNameUTF8String];

					BOOL builtProductsPathIsDir = NO;
					BOOL const builtProductsPathExists = [fileManager fileExistsAtPath:builtProductsDir isDirectory:&builtProductsPathIsDir];
					if (!builtProductsPathExists) {
						LOG_ERROR_printf("%s does not exist. Expected a directory at: %s\n", builtProductsDirEnvironmentName, builtProductsDirUTF8String);
					} else if (!builtProductsPathIsDir) {
						LOG_ERROR_printf("%s is not a directory. Expected a directory at: %s\n", builtProductsDirEnvironmentName, builtProductsDirUTF8String);
					} else {
						NSString *wrapperPath = [builtProductsDir stringByAppendingPathComponent:wrapperName];
						BOOL wrapperPathIsDir = NO;
						BOOL const wrapperPathExists = [fileManager fileExistsAtPath:wrapperPath isDirectory:&wrapperPathIsDir];

						if (!wrapperPathExists) {
							LOG_ERROR_printf("%s/%s does not exist. Expected a directory at: %s\n", builtProductsDirEnvironmentName, wrapperNameEnvironmentName, [wrapperPath UTF8String]);
						} else if (!wrapperPathIsDir) {
							LOG_ERROR_printf("%s/%s is not a directory. Expected a directory at: %s\n", builtProductsDirEnvironmentName, wrapperNameEnvironmentName, [wrapperPath UTF8String]);
						} else if (xcodeBuildSupportsNibArchiveFiles()) {
							[recursiveFileList addObject:wrapperPath];
						}
					}
				}
			}

			for(; 0 < [recursiveFileList count]; [recursiveFileList removeObjectAtIndex:0]) {
				NSString *path = [recursiveFileList firstObject];
				BOOL isDir = NO;
				if ([fileManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
					NSError *error = nil;
					for (NSString * const subpathComponent in [fileManager contentsOfDirectoryAtPath:path error:&error]) {
						NSString * const subpath = [path stringByAppendingPathComponent:subpathComponent];

						BOOL subpathIsDir = NO;
						BOOL const subpathExists = [fileManager fileExistsAtPath:subpath isDirectory:&subpathIsDir];
						if (subpathExists) {
							if (subpathIsDir) {
								[recursiveFileList insertObject:subpath atIndex:1];
							} else {
								if ([[[subpath pathExtension] lowercaseString] isEqualToString:NIB_FILE_EXTENSION_LOWER]) {
									[fileList addObject:subpath];
								}
							}
						}
					}
				} else {
					[fileList addObject:path];
				}
			}

			memmove(options, DefaultOptionValues, sizeof(options));
			mergeOptions(options, environmentOptions, options, ARRAY_ELEMENT_COUNT(options));
			mergeOptions(options, commandLineOptions, options, ARRAY_ELEMENT_COUNT(options));

			if (options[kOptionEnabled] == kOptionEnabled) {
				dispatch_group_t dispatchGroup = dispatch_group_create();
				dispatch_semaphore_t dispatchSemaphore = dispatch_semaphore_create(1);
				dispatch_queue_t dispatchQueue = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0);
				enum OptionValue * const settings = &options[0];
				NSMutableDictionary * const nibFileResults = [[NSMutableDictionary alloc] init];

				for (NSString * const nibPath in fileList) {
					NSError *nibReadError = nil;
					NSData *nibData = [NSData dataWithContentsOfFile:nibPath options:0 error:&nibReadError];
					if (nibData) {
						dispatch_group_async(dispatchGroup, dispatchQueue, ^{
							MMNibDataContainer *container = [[MMNibDataContainer alloc] init];
							container.path = nibPath;
							container.originalData = nibData;

							NSError *nibParseError = nil;
							MMNibArchive *archive = MM_autorelease([[MMNibArchive alloc] initWithData:container.originalData error:&nibParseError]);
							if (archive) {
								archive = smallerNibArchiveForOptions(archive, settings);
								NSData *archiveData = archive.data;

								if ([archiveData length] < [nibData length]) {
									container.updatedData = archiveData;
								}

							} else {
								if (GlobalLogLevel >= kLogLevelDebug) {
									fprintf(stderr, "%s: error: Could not parse file: %s\n", [container.path UTF8String], [[nibParseError description] UTF8String]);
								} else {
									fprintf(stderr, "%s: error: Could not parse file.\n", [container.path UTF8String]);
								}
							}

							long const semapthore_wait_result = dispatch_semaphore_wait(dispatchSemaphore, DISPATCH_TIME_FOREVER);
							assert(0 == semapthore_wait_result);
							[nibFileResults setObject:container forKey:nibPath];
							dispatch_semaphore_signal(dispatchSemaphore);

							MM_release(container);
						});
					} else if (nibReadError) {
						fprintf(stderr, "%s: error: Could not read file: %s\n", [nibPath UTF8String], [[nibReadError localizedDescription] UTF8String]);
					}

					writeCompletedNibFiles(dispatchSemaphore, nibFileResults);
				}

				dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
				writeCompletedNibFiles(dispatchSemaphore, nibFileResults);

				MM_release(nibFileResults);
				MM_release(fileManager);
#if !__has_feature(objc_arc)
				dispatch_release(dispatchGroup);
				dispatch_release(dispatchSemaphore);
#endif
			} // options[kOptionEnabled]
		} // @autoreleasepool
	}

	return e;
}

@implementation MMNibDataContainer
- (void)dealloc {
	MM_release(_path);
	MM_release(_originalData);
	MM_release(_updatedData);
	MM_super_dealloc;
}
@end

