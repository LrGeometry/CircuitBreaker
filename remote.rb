require "json"

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
        if block_given? then
          yield buf, buf.length, response["binaryLength"] # report progress
        end
      end
      return buf
    else
      return response["response"]
    end
  end
end
