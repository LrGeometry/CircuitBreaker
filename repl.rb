require "bundler/setup"
require "websocket-eventmachine-server"
require "thread"
require "json"
require "pry"
require "base64"

require_relative "dsl.rb"
require_relative "remote.rb"

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
    bind.eval(File.read("standard_switch.rb"), "standard_switch.rb")
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
