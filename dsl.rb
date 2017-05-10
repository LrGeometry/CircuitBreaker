require_relative "type.rb"
require_relative "pointer.rb"
require_relative "functionpointer.rb"

module Types
  Void		= NumericType.new("void",    "C",  1)
  Char		= NumericType.new("char",    "C",  1)
  Uint8		= NumericType.new("uint8",   "C",  1)
  Uint16	= NumericType.new("uint16",  "S<", 2)
  Uint32	= NumericType.new("uint32",  "L<", 4)
  Uint64	= NumericType.new("uint64",  "Q<", 8)
  Int8		= NumericType.new("int8",    "c",  1)
  Int16		= NumericType.new("int16",   "s<", 2)
  Int32		= NumericType.new("int32",   "l<", 4)
  Int64		= NumericType.new("int64",   "q<", 8)
  Float64	= NumericType.new("float32", "E",  8)
  Bool		= BooleanType.new

  class << Float64
    def coerce_to_argument(value)
      [value].pack("E").unpack("L<L<")
    end
    
    def coerce_from_return(switch, pair)
      pair.pack("L<L<").unpack("E")[0]
    end
  end
  
  class << Void
    def is_supported_return_type?
      true
    end
  end
end

class SwitchDSL
  def initialize(switch)
    @switch = switch
  end

  attr_accessor :bind
  attr_accessor :switch
  
  def load(file)
    bind.eval(File.read(file), file)
    nil
  end
  
  def base_addr
    @base_addr||= Pointer.from_switch(@switch,
                                      @switch.command("get", {:field => "baseAddr"})["value"])
  end
  
  def main_addr
    @main_addr||= Pointer.from_switch(@switch,
                                      @switch.command("get", {:field => "mainAddr"})["value"])
  end
  
  def sp
    @sp||= Pointer.from_switch(@switch,
                               @switch.command("get", {:field => "sp"})["value"])
  end

  def tls
    Pointer.from_switch(@switch,
                        @switch.command("get", {:field => "tls"})["value"])
  end
  
  def mref(off)
    main_addr + off
  end
  
  def invoke_gc
    @switch.command("invokeGC", {})
    nil
  end
  
  def malloc(size)
    Pointer.from_switch(@switch,
                        @switch.command("malloc", {:length => size})["address"])
  end

  def new(type, count=1)
    malloc(type.size * count).cast!(type)
  end

  def nullptr
    Pointer.new(@switch, 0)
  end
  
  def string_buf(string)
    buf = malloc(string.length + 1)
    buf.cast! Types::Char
    buf.write(string)
    buf[string.length] = 0
    return buf
  end
  
  def free(pointer)
    pointer.free
  end

  def jsrepl
    require "readline"
    while buf = Readline.readline("> ", true) do
      if buf == "exit" || buf == "quit" then
        break
      else
        puts @switch.command("eval", {:code => buf})["returnValue"]
      end
    end
  end
end