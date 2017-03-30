require "bundler/setup"
require "websocket-eventmachine-server"
require "thread"
require "json"
require "pry"
require "base64"

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
    @switch.command("free", {:address => pointer.to_switch})
    nil
  end
end

class RemoteSwitch
  def initialize(ws, cmdQueue, binQueue)
    @ws = ws
    @cmdQueue = cmdQueue
    @binQueue = binQueue
  end
  
  def command(type, params)
    jobTag = (Time.now.to_f * 1000).to_i
    json = JSON.generate({:command => type, :jobTag => jobTag}.merge(params))
    @ws.send json

    response = @cmdQueue.pop
    if response["command"] != "return" then
      raise "Got bad resposne packet: " + msg
    end

    if response["jobTag"] != jobTag then
      raise "got back wrong job tag"
    end
    if response["error"] then
      raise "remote error: " + response["error"].to_s
    end

    isBinary = response["binaryPayload"]
    if isBinary then
      buf = String.new
      while buf.length < response["binaryLength"] do
        buf+= @binQueue.pop
      end
      return buf
    else
      return response["response"]
    end
  end
end

wsQueue = Queue.new
cmdQueue = Queue.new
binQueue = Queue.new

Thread.new do
  puts "Waiting for connection from switch..."
  ws = wsQueue.pop
  puts "Got connection from switch"
  ws.onclose do
    puts "Lost connection from switch"
    
    EventMachine::stop_event_loop
    exit 1
  end

  dsl = SwitchDSL.new(RemoteSwitch.new(ws, cmdQueue, binQueue))
  bind = dsl.instance_eval do
    binding
  end
  dsl.bind = bind
  
  Pry.config.hooks.delete_hook(:before_session, :default)
  
  begin
    bind.eval(File.read("standardSwitch.rb"), "standardSwitch.rb")
    bind.pry
  rescue => e
    puts e
    puts e.backtrace
  end

  EventMachine::stop_event_loop
  exit 0
end

EM.run do
  WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 8080) do |ws|
    ws.onopen do |handshake|
      wsQueue.push ws
    end

    ws.onclose do
      puts "Connection closed"
    end

    ws.onmessage do |msg, type|
      if type == :text then
        data = JSON.parse(msg)
        if data["command"] == "log" then
          puts data["message"]
        else
          cmdQueue.push data
        end
      elsif type == :binary then
        binQueue.push msg
      else
        puts "?!?!"
      end
    end

    ws.onerror do |err|
      puts "got error: " + err.to_s
    end
  end
end
