# Circuit Breaker

This is Circuit Breaker, a Nintendo Switch hacking toolkit. It is heavily based upon [the PegaSwitch toolkit](https://pegaswitch.com/) and the ReSwitched team deserves a huge amount of credit for their work, without which this project would be impossible.

Issues and pull requests are welcome!

# Usage

## Installation

Make sure you have all the ruby gems installed. Installing ruby and bundler are outside of the scope of this document.

```
$ bundle install
```

If you intend to use Tracer, you'll have to install [my fork of Unicorn](https://github.com/misson20000/unicorn/tree/all_fixes) (at least until my changes get merged), [the Ruby bindings in that fork](https://github.com/misson20000/unicorn/tree/all_fixes/bindings/ruby), and [Crabstone](https://github.com/bnagy/crabstone).

If you intend to use the browser-based Pegasus exploit, you'll have to install the npm packages to run the DNS/HTTP server.

```
$ cd exploit/pegasus/
$ npm install
```

# The REPL

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
  * `Types::Result` (result.rb)
  * `Types::File`
  * `Types::DirInfo`
  * `Types::MemInfo`
  * `Types::PageInfo`

Pointer types can be obtained by calling the `#pointer` method on any other type object, including pointer type objects. The size of a type can also be read with `#size`

```
[1] pry(#<PegasusDSL>)> Types::MemInfo
=> struct MemInfo
[2] pry(#<PegasusDSL>)> Types::MemInfo.pointer
=> struct MemInfo*
[3] pry(#<PegasusDSL>)> Types::MemInfo.size
=> 32
[4] pry(#<PegasusDSL>)> Types::MemInfo.pointer.size
=> 8
```

### malloc

The `malloc` command will allocate a buffer on the JavaScript heap and return a void pointer object (not type object) to it. It takes the number of bytes to allocate as a parameter.

```
[1] pry(#<PegasusDSL>)> buffer = malloc 40
=> void* = 0x3ae1dcdf30
[2] pry(#<PegasusDSL>)> buffer2 = malloc(0x1024)
=> void* = 0x3ae1a71c00
```

In Ruby, parentheses are optional on method calls. Because pointers are represented by objects (see `pointer.rb`), they may be stored in variables.

Buffers may be freed with `free`.

```
[1] pry(#<PegasusDSL>)> free buffer
=> nil
```

### Pointer Objects

If you ever need a pointer to an arbitrary location in memory, you can create one with `make_pointer`.

```
[1] pry(#<PegasusDSL>)> my_pointer = make_pointer(0xDEADBEEF)
=> void* = 0xdeadbeef
```

The referenced address can be accessed with `#value`.

```
[1] pry(#<PegasusDSL>)> my_pointer.value
=> 3735928559
[2] pry(#<PegasusDSL>)> my_pointer.value.to_s(16)
=> "deadbeef"
```

You can read and write memory at the location represented by a pointer with the `#read` and `#write` methods, which both operate on raw bytes regardless of the type of the pointer.

```
[1] pry(#<PegasusDSL>)> buffer.read(10)
=> "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
[2] pry(#<PegasusDSL>)> buffer.write("foobie bletch")
=> nil
[3] pry(#<PegasusDSL>)> buffer.read(10)
=> "foobie ble"
```

Note that strings in Ruby can be any binary data and are not null-terminated. As such, `Pointer#write` will not append a null-terminator. Data can be written to a file using `File.write` from the Ruby standard library.

```
[1] pry(#<PegasusDSL>)> File.write("dump", main_addr.read(0x10000))
=> 65536
```

Pointers can be casted to point to other types with `#cast` and `#cast!`. Note that these methods do not take the type to cast the pointer object itself to, but rather the type to cast the object to a pointer to.

```
[1] pry(#<PegasusDSL>)> u64buf = buffer.cast Types::Uint64
=> uint64* = 0x3ae1b8f090
[2] pry(#<PegasusDSL>)> buffer
=> void* = 0x3ae1b8f090
[3] pry(#<PegasusDSL>)> buffer.cast! Types::Char
=> char* = 0x3ae1b8f090
[4] pry(#<PegasusDSL>)> buffer
=> char* = 0x3ae1b8f090
```

A shorthand for allocating a memory buffer the size of a single structure (or other type) is to use `new` like in C++. It even returns a properly typed pointer.

```
[1] pry(#<PegasusDSL>)> foo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a770a0
```

A buffer can also quickly be freed with `#free`. It behaves just like the `free` command.

```
[1] pry(#<PegasusDSL>)> foo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a770a0
[2] pry(#<PegasusDSL>)> foo.free
=> nil
```

Pointers can be indexed with `#[]` just like in C. You can even do pointer arithmetic with `#+`. Even though it makes no sense, `void` pointers may also be indexed. The `void` type behaves as if it had a size of `1`, just like a `char` or `uint8`.

```
[1] pry(#<PegasusDSL>)> u64buf[0] = 1337
=> 1337
[2] pry(#<PegasusDSL>)> buffer[0]
=> 57
[3] pry(#<PegasusDSL>)> buffer[1]
=> 5
```

Note that indices given within the square brackets match behavior in C and are multiplied by the size of the type.

A shorthand (longhand actually, but it's more intuitive) for `buffer[0]` is to use `Pointer#deref` instead. Ruby syntax does not allow for C-style dereferencing.

### List of REPL Commands

#### `load <file>`

Executes the given file in the REPL context. Try `load`ing `dump_files.rb`, `walk_mem_list.rb`, `dump_memory.rb`, or `ipc_switch.rb`.

#### `malloc <size>`

Allocates a buffer, returns a void pointer to it.

```
[1] pry(#<PegasusDSL>)> buffer = malloc 40
=> void* = 0x3ae1b8f090
```

#### `new <type>`

Allocates a buffer big enough to hold a single instance of the given type and returns a typed pointer to it. Unlike C++, memory allocated with `new` is the same as memory allocated with `malloc` and both can be freed with `free`.

```
[1] pry(#<PegasusDSL>)> mem_info = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a777a0
```

#### `free <pointer>`

Frees the given memory region. On the Pegasus backend, this erases references to it so it can be garbage collected. On the Tracer backend, this adds the region to the free list so it is available for allocation again.

Behaviour when given a pointer not obtained from `malloc` or `new` is undefined.

#### `nullptr`

Returns the null pointer.

#### `string_buf <string>`

Allocates a buffer big enough to hold the given string (plus null terminator), stores it, and returns the buffer.

### Function Pointers/Bridges

A pointer can be converted to a function pointer by calling the `#bridge` method on it. The first parameter is the return type and all other parameters are parameter types. Varargs are not supported.

```
[1] pry(#<PegasusDSL>)> strlen = mref(0x43A6E8).bridge(Types::Uint32, Types::Char.pointer)
=> uint32 (*)(char*) = 0x4097c406e8
```

Parameters may be annotated with their names with the `#set_names` function. The signature may be presented by calling `#doc`.

```
[1] pry(#<PegasusDSL>)> strlen = mref(0x43A6E8).bridge(Types::Uint32, Types::Char.pointer).set_names("string")
=> uint32 (*)(char*) = 0x4097c406e8
[2] pry(#<PegasusDSL>)> strlen.doc
=> "uint32 (*)(char* string)"
```

The function may be invoked with `#call`.

```
[1] pry(#<PegasusDSL>)> string = "Hello, world!"
=> "Hello, world!"
[2] pry(#<PegasusDSL>)> buf = string_buf string
=> char* = 0x3ae1b89630
[3] pry(#<PegasusDSL>)> length = strlen.call(buf)
=> 13
```

If a string is passed where a `char*` is expected, a temporary buffer will be allocated, the string will be written to it (with a null terminator), the function will be called, and the temporary buffer will be freed.

```
[1] pry(#<PegasusDSL>)> strlen.call("foobie bletch")
=> 13
```

If an array is passed where a pointer is expected, a temporary buffer will be allocated, the contents of the array will be written to the buffer (each item will be coerced to the correct type), the function will be called, and the contents of the buffer will be written into the array.

### Structs

A struct type can be created via `StructType.new`.

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
[1] pry(#<PegasusDSL>)> memInfo = new Types::MemInfo
=> struct MemInfo* = 0x3ae1a77100
[2] pry(#<PegasusDSL>)> memInfo.deref
=> #<struct Struct::MemInfo base=void* = 0x0, pageSize=0, memoryState=0, memoryPermissions=0>
```

Assigning structs is untested.

A single field may be retrieved from a struct pointer using the `#arrow` method, named after the `->` operator in C.

```
[1] pry(#<PegasusDSL>)> memInfo.arrow(:pageSize)
=> 0
```

Pointers to individual fields within structs may also be retrieved with `#member_ptr`.

```
[1] pry(#<PegasusDSL>)> memInfo.member_ptr(:pageSize)
=> uint64* = 0x3ae19f4688
```

### `standard_switch.rb`

`standard_switch.rb` is automatically loaded on startup and defines some useful function bridges, including a few SVCs. It also monkey-patches `Pointer` to include a `#query_memory` method, which will return a `MemInfo` struct describing the memory location the pointer was in. It is a small wrapper around `SVC::QueryMemory`.

## The Pegasus Exploit

This is the exploit that PegaSwitch uses. It's based upon a garbage collection bug in WebKit and is currently the only way to run Circuit Breaker commands on an actual console.

First, start up the combination DNS/HTTP server found in `exploit/pegasus`. It has to be able to bind to ports 53 and 80. It doesn't (shouldn't) produce any console output, but leave it running in the background.

```
$ cd exploit/pegasus/
$ sudo node webserver.js
```

Then, start up the REPL. This will wait for the Switch to connect to it. It will exit when the Switch disconnects or crashes and you will have to restart it.

```
$ ruby repl.rb pegasus
```

Since the `pegasus` exploit is currently the default, specifying it explicitly is unnecessary.

```
$ ruby repl.rb
```

In your Switch's network settings, change the DNS server to the IP address of your machine. 

![Nintendo Switch network configuration screenshot](http://i.imgur.com/X2O3I5f.jpg)

Connect to the network. It should tell you that "registration is required to use this network."

![Nintendo Switch registration is required screenshot](http://i.imgur.com/cKowmjM.jpg)

It may take a moment for the expoit to work and the page might reload a few times. It will say `Connected to server` once everything is ready.

### List of Additional Pegasus REPL Commands

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
[1] pry(#<PegasusDSL>)> main_addr
=> void* = 0x4097806000
[2] pry(#<PegasusDSL>)> mref 0x800
=> void* = 0x4097806800
```

#### `invoke_gc`

Invokes the garbage collector.

#### `jsrepl`

Starts a REPL for running JavaScript on the switch. Use `exit` or `quit` to go back to the Circuit Breaker REPL.

### Development

In order to update `public/bundle.js`, you will have to run WebPack in the `client/` directory. I recommend leaving a terminal open runninng `webpack --watch`.

## Tracer

Not so much an exploit as an emulator. Based upon Unicorn, Tracer can be used to emulate a Switch given a RAM dump from the Pegasus backend.

### Obtaining a RAM Dump

You'll have to use the Pegasus exploit to do this. Once you get the Circuit Breaker REPL, load the memory dumper and create a memory dump.

```
$ ruby repl.rb
[1] pry(#<PegasusDSL>)> load "dump_memory.rb"
=> nil
[2] pry(#<PegasusDSL>)> dump_all_mem("memdump")
...
[3] pry(#<PegasusDSL>)> quit
```

### Loading Tracer

You'll have to specify both that you want to use Tracer and the location of your memory dump.

```
$ ruby repl.rb tracer memdump/
```

Tracer might take a while the first time you use a specific memory dump to set up the trace database. After that, you will get a Circuit Breaker REPL. Usage is almost identical to that of the Circuit Breaker REPL under Pegasus by design.

### Tracing

Currently unimplemented.

# License

```
Copyright 2017 misson20000

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
