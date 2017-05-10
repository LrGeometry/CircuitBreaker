require "bundler/setup"
require "websocket-eventmachine-server"
require "thread"

require_relative "../dsl.rb"
require_relative "../remote.rb"

wsQueue = Queue.new
cmdQueue = Queue.new
binQueue = Queue.new

Thread.new do
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
end

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
bind.eval(File.read("standard_switch.rb"), "standard_switch.rb")

module CircuitBreakerHelper
  def switch
    $dsl
  end

  def find_blank_region(size)
    memInfo = switch.new Types::MemInfo
    pageInfo = switch.new Types::PageInfo
    begin
      ptr = switch.main_addr
      SVC::QueryMemory.call(memInfo, pageInfo, ptr)
      while memInfo.arrow(:memoryPermissions) > 0 || memInfo.arrow(:pageSize) < size do
        ptr = ptr + memInfo.arrow(:pageSize)
        SVC::QueryMemory.call(memInfo, pageInfo, ptr)
      end
      return ptr
    ensure
      memInfo.free
      pageInfo.free
    end
  end

  def malloc_aligned(size, alignment=0x2000)
    buf = switch.malloc size+alignment
    return buf + ((alignment-(buf.value%alignment))%alignment)
  end
end
