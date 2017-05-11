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
      raise "Got bad resposne packet: " + response.to_s
    end

    if response["jobTag"] != jobTag then
      raise "got back wrong job tag"
    end
    if response["error"] then
      raise "remote error: " + response["error"].to_s
    end

    isBinary = response["binaryPayload"]
    if isBinary then
      if response["binaryLength"] < 0 then # multi stream
        packet = @cmdQueue.pop
        while packet["type"] != "finish" do
          chunk = nil
          if packet["hasChunk"] then
            chunk = @binQueue.pop
            if chunk.length != packet["length"] then
              raise "chunk length mismatch"
            end
          end
          yield packet["header"], chunk
          
          packet = @cmdQueue.pop
        end
      else # regular stream
        buf = String.new
        while buf.length < response["binaryLength"] do
          buf+= @binQueue.pop
          if block_given? then
            yield buf, buf.length, response["binaryLength"] # report progress
          end
        end
        return buf
      end
    else
      return response["response"]
    end
  end
end
