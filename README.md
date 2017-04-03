# Circuit Breaker

This is Circuit Breaker, a Nintendo Switch hacking toolkit. It is heavily based upon [the PegaSwitch toolkit](https://pegaswitch.com/) and the ReSwitched team deserves an incredible amount of credit for developing the exploit and reverse engineering userspace functions. 

# Usage

## Installation

First, install all the node packages.

```
$ npm install
```

Make sure you have all the ruby gems installed. Installing ruby and bundler are outside of the scope of this document.

```
$ bundle install
```

## Launching

Then, start up the combination DNS/HTTP server. It has to be able to bind to ports 53 and 80. It doesn't (shouldn't) produce any console output, but leave it running in the background.

```
$ sudo node webserver.js
```

Finally, start up the REPL. This will wait for the Switch to connect to it. This will exit when the Switch disconnects or crashes and you will have to restart it.

```
$ ruby repl.rb
```

In your Switch's network settings, change the DNS server to the IP address of your machine. 

![Nintendo Switch network configuration screenshot](http://i.imgur.com/X2O3I5f.jpg)

Connect to the network. It should tell you that "registration is required to use this network."

![Nintendo Switch registration is required screenshot](http://i.imgur.com/cKowmjM.jpg)

It may take a moment for the expoit to work and the page might reload a few times. It will say `Connected to server` once everything is ready.

## Using the REPL

This is a regular Ruby REPL just like `irb`, and if you know Ruby, you should feel right at home.

### The Type System

A list of standard types included in the Circuit Breaker REPL follows:

  * `Types::Char`
  * `Types::Uint8`
  * `Types::Uint16`
  * `Types::Uint32`
  * `Types::Uint64`
  * `Types::Int8`
  * `Types::Int16`
  * `Types::Int32`
  * `Types::Int64`
  * `Types::Float64` (limited support)
  * `Types::Bool`

Additional Switch-specific types and structures are defined in `standard_switch.rb`.

  * `Types::Handle`
  * `Types::Result`
  * `Types::File`
  * `Types::DirInfo`
  * `Types::MemInfo`
  * `Types::PageInfo`

Pointer types can be obtained by calling the `#pointer` method on any other type object, including pointer type objects. The size of a type can also be read with `#size`

```
[1] pry(#<SwitchDSL>)> Types::MemInfo
=> struct MemInfo
[2] pry(#<SwitchDSL>)> Types::MemInfo.pointer
=> struct MemInfo*
[3] pry(#<SwitchDSL>)> Types::MemInfo.size
=> 32
[4] pry(#<SwitchDSL>)> Types::MemInfo.pointer.size
=> 8
```

### malloc

The `malloc` command will allocate a buffer on the JavaScript heap and return a void pointer object (not type object) to it. It takes the number of bytes to allocate as a parameter.

```
[1] pry(#<SwitchDSL>)> buffer = malloc 40
=> void* = 0x3ae1dcdf30
[2] pry(#<SwitchDSL>)> buffer2 = malloc(0x1024)
=> void* = 0x3ae1a71c00
```

In Ruby, parentheses are optional on method calls. Because pointers are represented by objects (see `pointer.rb`), they may be stored in variables.

Buffers may be freed with `free`.

```
[1] pry(#<SwitchDSL>)> free buffer
=> nil
```

### Pointer Objects

If you ever need a pointer to an arbitrary location in memory, you can manually instantiate one.

```
[1] pry(#<SwitchDSL>)> my_pointer = Pointer.new(@switch, 0xDEADBEEF)
=> void* = 0xdeadbeef
```

The referenced address can be accessed with `#value`.

```
[1] pry(#<SwitchDSL>)> my_pointer.value
=> 3735928559
[2] pry(#<SwitchDSL>)> my_pointer.value.to_s(16)
=> "deadbeef"
```

You can read and write memory at the location represented by a pointer with the `#read` and `#write` methods, which both operate on raw bytes regardless of the type of the pointer.

```
[1] pry(#<SwitchDSL>)> buffer.read(10)
=> "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
[2] pry(#<SwitchDSL>)> buffer.write("foobie bletch")
=> nil
[3] pry(#<SwitchDSL>)> buffer.read(10)
=> "foobie ble"
```

Note that strings in Ruby can be any binary data and are not null-terminated. As such, `Pointer#write` will not append a null-terminator. Data can be written to a file using `File.write` from the Ruby standard library.

```
[1] pry(#<SwitchDSL>)> File.write("dump", main_addr.read(0x10000))
=> 65536
```

Pointers can be casted to point to other types with `#cast` and `#cast!`. Note that these methods do not take the type to cast the pointer object itself to, but rather the type to cast the object to a pointer to.

```
[1] pry(#<SwitchDSL>)> u64buf = buffer.cast Types::Uint64
=> uint64* = 0x3ae1b8f090
[2] pry(#<SwitchDSL>)> buffer
=> void* = 0x3ae1b8f090
[3] pry(#<SwitchDSL>)> buffer.cast! Types::Char
=> char* = 0x3ae1b8f090
[4] pry(#<SwitchDSL>)> buffer
=> char* = 0x3ae1b8f090
```

A shorthand for allocating a memory buffer the size of a single structure (or other type) is to use `new` like in C++. It even returns a properly typed pointer.

```
[1] pry(#<SwitchDSL>)> foo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a770a0
```

A buffer can also quickly be freed with `#free`. It behaves just like the `free` command.

```
[1] pry(#<SwitchDSL>)> foo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a770a0
[2] pry(#<SwitchDSL>)> foo.free
=> nil
```

Pointers can be indexed with `#[]` just like in C. You can even do pointer arithmetic with `#+`. Even though it makes no sense, `void` pointers may also be indexed. The `void` type behaves as if it had a size of `1`, just like a `char` or `uint8`.

```
[1] pry(#<SwitchDSL>)> u64buf[0] = 1337
=> 1337
[2] pry(#<SwitchDSL>)> buffer[0]
=> 57
[3] pry(#<SwitchDSL>)> buffer[1]
=> 5
```

Note that indices given within the square brackets match behavior in C and are multiplied by the size of the type.

A shorthand (longhand actually, but it's more intuitive) for `buffer[0]` is to use `Pointer#deref` instead. Ruby syntax does not allow for C-style dereferencing.

### List of REPL Commands

#### `load <file>`

Executes the given file in the REPL context. Try `load`ing `dumpFiles.rb` or `walkMemList.rb`.

#### `base_addr`

Returns the `base_addr` from PegaSwitch as a `void*`.

#### `main_addr`

Returns the `main_addr` from PegaSwitch as a `void*`.

#### `sp`

Returns the stack pointer from PegaSwitch as a `void*`.

#### `tls`

Returns a pointer to thread local storage as a `void*`.

#### `mref <offset>`

Returns a pointer offset from `main_addr` by the given amount. Useful for creating function bridges.

```
[1] pry(#<SwitchDSL>)> main_addr
=> void* = 0x4097806000
[2] pry(#<SwitchDSL>)> mref 0x800
=> void* = 0x4097806800
```

#### `invoke_gc`

Invokes the garbage collector.

#### `malloc <size>`

Allocates a buffer on the JavaScript heap, returns a void pointer to it.

```
[1] pry(#<SwitchDSL>)> buffer = malloc 40
=> void* = 0x3ae1b8f090
```

#### `new <type>`

Allocates a buffer (on the JavaScript heap) big enough to hold a single instance of the given type and returns a typed pointer to it.

```
[1] pry(#<SwitchDSL>)> mem_info = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a777a0
```

#### `free <pointer>`

Erases any references made by `malloc` or `new` to the given memory region and allows it to be garbage collected. This does not invoke the garbage collector and will fail silently if given a pointer that doesn't point to the start of a memory block allocated by `malloc` or `free`,

#### `nullptr`

Returns the null pointer.

#### `string_buf <string>`

Allocates a buffer big enough to hold the given string (plus null terminator), stores it, and returns the buffer.

### Function Pointers/Bridges

A pointer can be converted to a function pointer by calling the `#bridge` method on it. The first parameter is the return type and all other parameters are parameter types. Varargs are not supported.

```
[1] pry(#<SwitchDSL>)> strlen = mref(0x43A6E8).bridge(Types::Uint32, Types::Char.pointer)
=> uint32 (*)(char*) = 0x4097c406e8
```

Parameters may be annotated with their names with the `#set_names` function. The signature may be presented by calling `#doc`.

```
[1] pry(#<SwitchDSL>)> strlen = mref(0x43A6E8).bridge(Types::Uint32, Types::Char.pointer).set_names("string")
=> uint32 (*)(char*) = 0x4097c406e8
[2] pry(#<SwitchDSL>)> strlen.doc
=> "uint32 (*)(char* string)"
```

The function may be invoked with `#call`.

```
[1] pry(#<SwitchDSL>)> string = "Hello, world!"
=> "Hello, world!"
[2] pry(#<SwitchDSL>)> buf = string_buf string
=> char* = 0x3ae1b89630
[3] pry(#<SwitchDSL>)> length = strlen.call(buf)
=> 13
```

If a string is passed where a `char*` is expected, a temporary buffer will be allocated, the string will be written to it (with a null terminator), the function will be called, and the temporary buffer will be freed.

```
[1] pry(#<SwitchDSL>)> strlen.call("foobie bletch")
=> 13
```

If an array is passed where a pointer is expected, a temporary buffer will be allocated, the contents of the array will be written to the buffer (each item will be coerced to the correct type), the function will be called, and the contents of the buffer will be written into the array.

### Structs

A struct type may be created via `StructType.new`.

```
MemInfo = StructType.new("MemInfo") do
  field Types::Void.pointer, :base                                                                                                                                                       
  field Types::Uint64, :pageSize
  field Types::Uint64, :memoryState
  field Types::Uint64, :memoryPermissions
end
```

Structs may be forward-declared and their fields defined later via `StructType#def_fields`

```
LinkedNode = StructType.new("LinkedNode")
LinkedNode.def_fields do
  field TestStruct.pointer, :next
  field Types::Char.pointer, :name
end
```

Structs should probably be declared in files which can be loaded with `load`.

### Struct Pointers

Pointers to structs, when dereferences, will return an object containing all of the field values.

```
[1] pry(#<SwitchDSL>)> memInfo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a77100
[2] pry(#<SwitchDSL>)> memInfo.deref
=> #<struct Struct::MemInfo base=void* = 0x0, pageSize=0, memoryState=0, memoryPermissions=0>
```

Assigning structs is untested.

A single field may be retrieved from a struct pointer using the `#arrow` method, named after the `->` operator in C.

```
[1] pry(#<SwitchDSL>)> memInfo.arrow(:pageSize)
=> 0
```

Pointers to individual fields within structs may also be retrieved with `#member_ptr`.

```
[1] pry(#<SwitchDSL>)> memInfo.member_ptr(:pageSize)
=> uint64* = 0x3ae19f4688
```

### `standard_switch.rb`

`standard_switch.rb` is automatically loaded on startup and defines some useful function bridges, including a few SVCs. It also monkey-patches `Pointer` to include a `#query_memory` method, which will return a `MemInfo` struct describing the memory location the pointer was in. It is a small wrapper around `SVC::QueryMemory`.

# Development

### Important Files

```
client/ - Code for the switch-side exploit
client/handlers.js - Code for handling requests from network
client/index.js - Main entry and networking code
client/utils.js - Utilities, mostly for formatting and performing arithmetic on addresses
client/primitives.js - Exploit primitives, mostly equivalent to PegaSwitch's sploitcore.js
client/webpack.config.js - WebPack configuration

public/ - Web server root
public/bundle.js - Compiled switch-side exploit
public/index.html - HTML page
public/minmain.js - Initial exploit

functionpointer.rb - REPL code for function pointers
nro.rb - REPL code for parsing NRO structures, mostly untested and largely useless
pointer.rb - REPL for pointers
repl.rb - REPL entry point
standard_switch.rb - REPL typedefs and function bridges for the Switch
type.rb - REPL code for type system

dump_files.rb - Module for dumping files from the Switch filesystem
walk_mem_list.rb - Module for querying all memory pages on the Switch
```

In order to update `public/bundle.js`, you will have to run WebPack in the `client/` directory. I recommend leaving a terminal open runninng `webpack --watch`.

Issues and pull requests are welcome!

# License

```
Copyright 2017 misson20000

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```