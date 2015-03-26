# NibArchive File Format
This is a basic description of the NibArchive file format.
It was made by observing the input and output of the ibtool(1)
executable. 

## File Layout
File Content | Description
:------------|:------------
`NIBArchive` | 10 bytes secifying this is a NibArchive file.
uint32 LE    | Constant 1.
uint32 LE    | Constant 9.
uint32 LE    | Object count.
uint32 LE    | File offset for objects data.
uint32 LE    | Key count.
uint32 LE    | File offset for keys data.
uint32 LE    | Value count.
uint32 LE    | File offset for values data.
uint32 LE    | Class name count.
uint32 LE    | File offset for class name data.
objects      | Sequentially coded objects.
keys         | Sequentially coded keys.
values       | Sequentially coded values.
class names  | Sequentially coded class names.

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
`0`: int8, 1 byte <br/>
`1`: int16 LE, 2 bytes <br/>
`2`: int32 LE, 4 bytes <br/>
`3`: int64 LE, 8 bytes <br/>
`4`: true <br/>
`5`: false <br/>
`6`: float, 4 bytes <br/>
`7`: double, 8 bytes <br/>
`8`: data, varint , number of bytes as specified in varint <br/>
`9`: nil <br/>
`10`: object reference, 4 bytes uint32 LE coding an offset into the list of objects <br/>
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
