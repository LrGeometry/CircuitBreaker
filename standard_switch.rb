load "result.rb"

module Types
  Handle = Types::Uint32.typedef("Handle")
  SessionHandle = Types::Handle.typedef("SessionHandle")  
  File = Types::Void.typedef("FILE")
  DirInfo = Types::Void.typedef("DirInfo")
  MemInfo = StructType.new("MemInfo") do
    field Types::Void.pointer, :base # virtual address
    field Types::Uint64, :pageSize
    field Types::Uint64, :memoryState
    field Types::Uint64, :memoryPermissions
  end
  PageInfo = StructType.new("PageInfo") do
    field Types::Uint64, :pageFlags
  end
end

$dsl = self

module Bridges
  @strlen = $dsl.mref(0x43A6E8).bridge(Types::Uint32, Types::Char.pointer)
  @smGetServiceHandle = $dsl.mref(0x3AD15C).bridge(Types::Result, Types::SessionHandle.pointer, Types::Char.pointer, Types::Uint32).set_names("session", "name", "length")
  @fseek = $dsl.mref(0x438B18).bridge(Types::Void, Types::File.pointer, Types::Uint32, Types::Uint32)
  @ftell = $dsl.mref(0x438BE0).bridge(Types::Uint32, Types::File.pointer)
  @fopen = $dsl.mref(0x43DDB4).bridge(Types::File.pointer, Types::Char.pointer, Types::Char.pointer)
  @fread = $dsl.mref(0x438A14).bridge(Types::Int32, Types::Void.pointer, Types::Uint32, Types::Uint32, Types::File.pointer)
  @fclose = $dsl.mref(0x4384D0).bridge(Types::Uint32, Types::File.pointer)
  @memcpy = $dsl.mref(0x44338C).bridge(Types::Uint32, Types::Void.pointer, Types::Void.pointer, Types::Uint32)
  @openDirectory = $dsl.mref(0x233894).bridge(Types::Uint32, Types::Handle.pointer, Types::Char.pointer, Types::Uint32)
  @readDirectory = $dsl.mref(0x2328B4).bridge(Types::Uint32, Types::DirInfo.pointer, Types::Uint32.pointer, Types::Handle, Types::Uint64)
  @closeDirectory = $dsl.mref(0x232828).bridge(Types::Uint32, Types::Handle.pointer)
  
  @sendSyncRequestWrapper = $dsl.mref(0x3ace5c).bridge(Types::Uint32, Types::SessionHandle, Types::Void.pointer, Types::Uint32).set_names("session", "command", "command_length")
  
  class << self
    attr_reader :strlen
    attr_reader :smGetServiceHandle
    attr_reader :fseek
    attr_reader :ftell
    attr_reader :fopen
    attr_reader :fread
    attr_reader :fclose
    attr_reader :memcpy
    attr_reader :openDirectory
    attr_reader :readDirectory
    attr_reader :closeDirectory
    attr_reader :sendSyncRequestWrapper
  end
end

module SVC
  svc = {
    0x01 => $dsl.mref(0x3BBE10),
    0x02 => $dsl.mref(0x3BBE28),
    0x03 => $dsl.mref(0x3BBE30),
    0x04 => $dsl.mref(0x3BBE38),
    0x05 => $dsl.mref(0x3BBE40),
    0x06 => $dsl.mref(0x3BBE48),
    0x07 => $dsl.mref(0x3BBE60),
    0x08 => $dsl.mref(0x3BBE68),
    0x09 => $dsl.mref(0x3BBE80),
    0x0A => $dsl.mref(0x3BBE88),
    0x0B => $dsl.mref(0x3BBE90),
    0x0C => $dsl.mref(0x3BBE98),
    0x0D => $dsl.mref(0x3BBEB0),
    0x0E => $dsl.mref(0x3BBEB8),
    0x0F => $dsl.mref(0x3BBED8),
    0x10 => $dsl.mref(0x3BBEE0),
    0x11 => $dsl.mref(0x3BBEE8),
    0x12 => $dsl.mref(0x3BBEF0),
    0x13 => $dsl.mref(0x3BBEF8),
    0x14 => $dsl.mref(0x3BBF00),
    0x15 => $dsl.mref(0x3BBF08),
    0x16 => $dsl.mref(0x3BBF20),
    0x17 => $dsl.mref(0x3BBF28),
    0x18 => $dsl.mref(0x3BBF30),
    0x19 => $dsl.mref(0x3BBF48),
    0x1A => $dsl.mref(0x3BBF50),
    0x1B => $dsl.mref(0x3BBF58),
    0x1C => $dsl.mref(0x3BBF60),
    0x1D => $dsl.mref(0x3BBF68),
    #0x1E => ,
    0x1F => $dsl.mref(0x3BBF70),
    #0x20 => ,
    0x21 => $dsl.mref(0x3BBF88),
    0x22 => $dsl.mref(0x3BBF90),
    #0x23 => 0x,
    #0x24 => 0x,
    0x25 => $dsl.mref(0x3BBF98),
    0x26 => $dsl.mref(0x3BBFB0),
    0x27 => $dsl.mref(0x3BBFB8),
    0x28 => $dsl.mref(0x3BBFC0),
    0x29 => $dsl.mref(0x3BBFC8),
    #0x2A-0x4F
    0x50 => $dsl.mref(0x3BBFE0),
    0x51 => $dsl.mref(0x3BBFF8),
    0x52 => $dsl.mref(0x3BC000)
  }

  # can only be invoked once according to PegaSwitch guys, and it's already been blown by the time our code runs
  CreateMemoryHeap = svc[0x01].bridge(Types::Result, Types::Handle.pointer, Types::Uint64).set_names("handle", "size")

  # can change RW -> R
  SetMemoryPermission = svc[0x02].bridge(Types::Result, Types::Void.pointer, Types::Uint64, Types::Uint64).set_names("???", "size", "permission")

  # untested
  MapMemory_maybe = svc[0x04].bridge(Types::Result, Types::Uint64, Types::Uint64, Types::Uint64)

  # untested
  UnmapMemory_maybe = svc[0x05].bridge(Types::Result, Types::Uint64, Types::Uint64, Types::Uint64)

  # working
  QueryMemory = svc[0x06].bridge(Types::Result, Types::MemInfo.pointer, Types::PageInfo.pointer, Types::Void.pointer).set_names("memoryInfo", "pageInfo", "addr")

  # untested
  ExitProcess = svc[0x07].bridge(Types::Void)

  # untested
  CreateThread = svc[0x08].bridge(Types::Void, Types::Handle.pointer, Types::Void.pointer, Types::Uint64, Types::Void.pointer, Types::Int32, Types::Int32).set_names("out", "entrypoint", "arg", "stackTop", "priority", "coreNumber")

  # untested
  StartThread = svc[0x09].bridge(Types::Void, Types::Handle).set_names("thread")

  # untested
  ExitThread = svc[0x0A].bridge(Types::Void)

  # working
  SleepThread = svc[0x0B].bridge(Types::Void, Types::Int64).set_names("nanoseconds")

  # working
  GetCurrentCoreNumber = svc[0x10].bridge(Types::Int32)

  # broken - no perms?
  CreateMemoryBlock = svc[0x50].bridge(Types::Result, Types::Handle.pointer, Types::Uint64, Types::Uint64, Types::Uint64).set_names("memBlock", "size", "myPerm", "otherPerm")

  # no perms?
  MapMemoryBlock = svc[0x13].bridge(Types::Result, Types::Handle, Types::Uint64, Types::Uint64, Types::Uint64).set_names("memBlock", "addr", "size", "perm")

  # no perms?
  UnmapMemoryBlock = svc[0x14].bridge(Types::Result, Types::Handle).set_names("memBlock")

  # untested
  ConnectToPort = svc[0x1F].bridge(Types::Result, Types::SessionHandle.pointer, Types::Char.pointer).set_names("out", "portName")

  # untested
  SendSyncRequest = svc[0x21].bridge(Types::Result, Types::SessionHandle).set_names("session")

  # untested
  SendSyncRequestEx = svc[0x22].bridge(Types::Result, Types::Void.pointer, Types::Uint64, Types::SessionHandle).set_names("addr", "size", "session")
end

class Pointer
  def query_memory
    memInfo = $dsl.new Types::MemInfo
    pageInfo = $dsl.new Types::PageInfo

    SVC::QueryMemory.call(memInfo, pageInfo, self)

    struct = memInfo.deref
    
    $dsl.free pageInfo
    $dsl.free memInfo

    return struct
  end
end
