class ResultCode
  def initialize(number, description)
    @number = number
    @mod_no = number & 0x1FF
    @num_desc = number >> 9
    @description = description
  end

  @@cache = {}
  @@known_mods = {
    1 => "Kernel",
    2 => "FS",
    5 => "GameCard",
    9 => "RO service",
    10 => "IPC",
    11 => "IPC",
    16 => "NS",
    21 => "SM",
    22 => "RO user",
    124 => "Account",
    126 => "Mii",
    203 => "HID"
  }
  
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

  def mod_name
    @@known_mods[@mod_no] || "unknown"
  end
  
  def to_s
    return "0x" + number.to_s(16) + " (" + (@description ? @description.to_s : "unknown") + " mod #{mod_name})"
  end
  
  def inspect
    to_s
  end

  def to_i
    @number
  end

  def ==(other)
    @number == other.to_i
  end
end

# http://switchbrew.org/index.php?title=Error_codes&oldid=429
{
  0x0000 => "OK",
  0x1015 => "no such service/access denied",
  0xCA01 => "Invalid size (not page-aligned)",
  0xCC01 => "Invalid address (not page-aligned)",
  0xD201 => "Handle-table full.",
  0xD401 => "Invalid memory state.",
  0xD801 => "Can't set executable permission.",
  0xDC01 => "Stack address outside allowed range.",
  0xE001 => "Invalid thread priority.",
  0xE201 => "Invalid processor ID.",
  0xE401 => "Invalid handle.",
  0xE601 => "Syscall copy from user failed.",
  0xEA01 => "Time out? When you give 0 handles to svcWaitSynchronizationN.",
  0xEE01 => "When you give too many handles to svcWaitSynchronizationN.",
  0xF201 => "No such port",
  0xF801 => "Unhandled usermode exception",
  0xFA01 => "Wrong memory permission?",
  0x10601 => "Port max sessions exceeded.",
  0x10801 => "Out of memory",
  0x7D402 => "Permission denied or title-id not found",
  0x13B002 => "Gamecard not inserted",
  0x171402 => "Invalid gamecard handle.",
  0x1A4A02 => "Out of memory",
  0x196002 => "Out of memory",
  0x196202 => "Out of memory",
  0x2EE202 => "Unknown media-id",
  0x2EE602 => "Path too long",
  0x2F5A02 => "Offset outside storage",
  0x313802 => "Operation not supported",
  0x320002 => "Permission denied",
  0xDC05 => "Gamecard not inserted",
  0x6609 => "Invalid memory state/permission",
  0x6A09 => "Invalid Nrr",
  0xA209 => "Unaligned Nrr address",
  0xA409 => "Bad Nrr size",
  0xAA09 => "Bad Nrr address",
  0x1A80A => "Bad magic (expected 'SFCO')",
  0x20B => "Size too big to fit to marshal",
  0x11A0B => "Went past maximum during marhsalling.",
  0x0C15 => "Invalid name (all zeroes)",
  0x816 => "Bad Nro magic",
  0xC16 => "Bad Nrr magic"
}.each_pair do |k, v|
  ResultCode.known(k, v)
end

ResultCode::OK = ResultCode.get(0)

module Types
  Result = NumericType.new("Result", "L<", 4)
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
