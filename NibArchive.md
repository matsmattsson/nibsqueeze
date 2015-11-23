# NibArchive File Format
This is a description of the NibArchive file format. It is used by UIKit on iOS 6 and later.
The details were discovered by manipulating the input and observing the output of the ibtool(1) executable.

Nib files are a serialization format for UI-objects. They are then instantiated with the NSCoder API.
The file format reflects this, as all encoded types corresponds to one NSCoder method. It may also
be that the file format supports more types, but it is not possible to find them with ibtool.


## File Layout
The file is using a common data layout of a header and data values. The header
contains a hardcoded file identifier, some integers that may be a version number,
and a list of offsets of where to find the different types of data.

The data is consists of four lists. It is, a list of objects, a list of keys,
a list of values, and a list of class names.

Each item in the list of objects specifies a class and a range of indexes into
the list of values.

The list of keys is essenitally an array of strings.

The list of values stores a key for each value, the type of the object, and
some data related to the type of object.

The list of class names is mostly a list of strings.

The following table gives a more detailed description of how to parse the file.


Byte offset        | File Content | Description
:------------------|:-------------|:------------
0 to 9             | `NIBArchive` | 10 bytes secifying this is a NibArchive file.
10 to 13           | uint32 LE    | Constant 1.
14 to 17           | uint32 LE    | Constant 9.
18 to 21           | uint32 LE    | Object count.
22 to 25           | uint32 LE    | File offset for objects data.
26 to 29           | uint32 LE    | Key count.
30 to 33           | uint32 LE    | File offset for keys data.
34 to 37           | uint32 LE    | Value count.
38 to 41           | uint32 LE    | File offset for values data.
42 to 45           | uint32 LE    | Class name count.
46 to 49           | uint32 LE    | File offset for class name data.
see bytes 18 to 25 | objects      | Sequentially coded objects.
see bytes 26 to 33 | keys         | Sequentially coded keys.
see bytes 34 to 41 | values       | Sequentially coded values.
see bytes 42 to 49 | class names  | Sequentially coded class names.

#### Varint coding
To save space for coding integer, the NibArchive file has a variable length coding
of integers. I have only seen integers coded as two bytes, so how this extends to larger values is an
unverifived assumption.

It codes integers in 7-bit chunks, little-endian order. The high-bit in each byte signifies if it is the
last byte.

Value        | Bitcoding
:------------|:------
0 to 127     | `1`b<sub>6</sub>b<sub>5</sub>b<sub>4</sub>b<sub>3</sub>b<sub>2</sub>b<sub>1</sub>b<sub>0</sub>
128 to 16383 | `0`b<sub>6</sub>b<sub>5</sub>b<sub>4</sub>b<sub>3</sub>b<sub>2</sub>b<sub>1</sub>b<sub>0</sub>, `1`b<sub>13</sub>b<sub>12</sub>b<sub>11</sub>b<sub>10</sub>b<sub>9</sub>b<sub>8</sub>b<sub>7</sub>

#### Object coding
File Content | Description
-------------|:------------
varint       | Class name index. The object’s class is specified as an offset into the list of class names.
varint       | Values index. The values stored for an object is specified as an offset and length into the list of values.
varint       | Value count.

#### Key coding
File Content | Description
:------------|:------------
varint       | Key name length.
UTF-8 string | Key name. It is not null terminated.

#### Value coding
<table>
<tr><th align=left>File Content</th><th align=left>Description</th></tr>
<tr><td>varint</td><td>Key index. The key used for retreiving the value. It is an offset into the list of keys.</td></tr>
<tr><td>uint8</td><td>Value type:<br/>
<code>0</code>: int8, 1 byte <br/>
<code>1</code>: int16 LE, 2 bytes <br/>
<code>2</code>: int32 LE, 4 bytes <br/>
<code>3</code>: int64 LE, 8 bytes <br/>
<code>4</code>: true <br/>
<code>5</code>: false <br/>
<code>6</code>: float, 4 bytes <br/>
<code>7</code>: double, 8 bytes <br/>
<code>8</code>: data, varint , number of bytes as specified in varint <br/>
<code>9</code>: nil <br/>
<code>10</code>: object reference, 4 bytes uint32 LE coding an offset into the list of objects <br/>
</td></tr>
<tr><td></td><td>Data depending on value type.</td></tr>
</table>

#### Class name coding
File Content | Description
:------------|:------------
varint       | Length of class name string.
varint       | Number of extra int32 values. Only values 0 and 1 has been observed.
int32 LE\*   | Extra int32 values.
string       | Class name string.
