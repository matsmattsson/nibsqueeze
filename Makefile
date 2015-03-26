
.PHONY: all clean

all: bin/nibsqueeze

HEADERS = src/DeduplicateConstantObjects.h \
          src/DeduplicateValueInstances.h \
          src/MergeEqualObjects.h \
          src/MergeValues.h \
          src/MMMacros.h \
          src/MMNibArchive.h \
          src/MMNibArchiveClassName.h \
          src/MMNibArchiveObject.h \
          src/MMNibArchiveValue.h \
          src/StripUnusedClassNames.h \
          src/StripUnusedValues.h

SOURCES = src/DeduplicateConstantObjects.m \
          src/DeduplicateValueInstances.m \
          src/main.m \
          src/MergeEqualObjects.m \
          src/MergeValues.m \
          src/MMNibArchive.m \
          src/MMNibArchiveClassName.m \
          src/MMNibArchiveObject.m \
          src/MMNibArchiveValue.m \
          src/StripUnusedClassNames.m \
          src/StripUnusedValues.m

bin:
	mkdir -p bin

bin/nibsqueeze: bin Makefile $(HEADERS) $(SOURCES)
	$(CC) -o $@ -framework Foundation -Werror -fno-objc-arc -Os $(CFLAGS) $(SOURCES)

clean:
	rm bin/nibsqueeze || true

