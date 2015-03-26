# nibsqueeze
Reduce size of compiled nib-files.

The number of bytes saved for a nib-file depends
on its content, but common results are savings from
1% to 10%.

Supports iOS target version 6.0 and later.

## Xcode Integration
nibsqueeze is designed for easy integration in the
Xcode build process. It will look for the environment
variables that Xcode sets and automatically find the
built product and the containing nib-files.

In the Xcode target settings, add a custom Run-Script
build phase. In it, just drag the nibsqueeze binary
to the text field and Xcode will type the full path.
