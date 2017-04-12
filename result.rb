class ResultCode
  def initialize(number, description)
    @number = number
    @description = description
  end

  @@cache = {}
  
  def self.get(id)
    if @@cache[id] then
      return @@cache[id]
    else
      @@cache[id] = self.new(id, nil)
      return @@cache[id]
    end
  end

  def self.known(id, description)
    @@cache[id] = self.new(id, description)
  end
  
  attr_reader :number
  attr_accessor :description
  
  def value
    @number
  end

  def to_s
    return "0x" + number.to_s(16) + " (" + (@description ? @description.to_s : "unknown") + ")"
  end
  
  def inspect
    to_s
  end
end

ResultCode.known(0x0000, "OK")
ResultCode.known(0x1015, "no such service/access denied")
ResultCode.known(0xCA01, "Invalid size (not page-aligned")
ResultCode.known(0xCC01, "Invalid address (not page-aligned)")
ResultCode.known(0xD201, "Handle-table full.")
ResultCode.known(0xD401, "Invalid memory state.")
ResultCode.known(0xD801, "Can't set executable permission.")
ResultCode.known(0xE401, "Invalid handle.")
ResultCode.known(0xE601, "Syscall copy from user failed.")
ResultCode.known(0xEA01, "Time out? When you give 0 handles to svcWaitSynchronizationN.")
ResultCode.known(0xEE01, "When you give too many handles to svcWaitSynchronizationN.")
ResultCode.known(0xFA01, "Wrong memory permission?")
ResultCode.known(0x10601, "Port max sessions exceeded.")
ResultCode.known(0x7D402, "Title-id not found")
ResultCode.known(0x0C15, "Invalid name (all zeroes")
ResultCode.known(0x1015, "Permission denied")

module Types
  Result = NumericType.new("Result", "l<", 4)
  class << Result
    def encode(value)
      if value.is_a? ResultCode then
        value = value.number
      end
      [value].pack(@packing)
    end

    def decode(switch, string)
      ResultCode.get(string.unpack(@packing)[0])
    end

    def coerce_to_argument(switch, value, finalizers)
      if value.is_a? ResultCode then
        value = value.number
      end
      [value].pack("Q<").unpack("L<L<")
    end

    def coerce_from_return(switch, pair)
      ResultCode.get(pair.pack("L<L<").unpack("Q<")[0])
    end
  end
end
