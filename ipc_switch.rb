module IPC
  def self.create_message(&block)
    dsl = IPC::IPCMessage.new
    dsl.instance_exec(&block)
    return dsl.pack
  end

  class IPCMessage
    def initialize(xDescriptors = [],
                   aDescriptors = [],
                   bDescriptors = [],
                   wDescriptors = [],
                   data = String.new,
                   cDescriptor = nil,
                   handleDescriptor = nil)
      @xDescriptors = xDescriptors
      @aDescriptors = aDescriptors
      @bDescriptors = bDescriptors
      @wDescriptors = wDescriptors
      @data = data
      @cDescriptor = cDescriptor
      @handleDescriptor = handleDescriptor
    end
    
    def self.unpack(io)
      origin = io.pos
      words = io.read(8).unpack("L<L<")
      ipcVersion       = (words[0] >>  0) & 0xFFFF
      numXDescriptors  = (words[0] >> 16) & 0x000F
      numADescriptors  = (words[0] >> 20) & 0x000F
      numBDescriptors  = (words[0] >> 24) & 0x000F
      numWDescriptors  = (words[0] >> 28) & 0x000F
      dataSize         = (words[1] >>  0) & 0x03FF
      cDescriptor      = (words[1] >> 10) & 0x0007
      handleDescriptor = (words[1] >> 31) & 0x0001
      
      if ipcVersion != 4 then
        puts "bad IPC version: " + ipcVersion.to_s
      end

      v_handleDescriptor = handleDescriptor > 0 ? HandleDescriptor.unpack(io) : nil

      v_xDescriptors = numXDescriptors.times.map do |_|
        BufferDescriptorX.unpack(io)
      end
      v_aDescriptors = numADescriptors.times.map do |_|
        BufferDescriptorAB.unpack(io)
      end
      v_bDescriptors = numBDescriptors.times.map do |_|
        BufferDescriptorAB.unpack(io)
      end
      v_wDescriptors = numWDescriptors.times.map do |_|
        BufferDescriptorW.unpack(io)
      end

      padding = (((io.pos-origin)/16.0).ceil*16.0)-(io.pos-origin)
      if padding == 0 then
        padding = 16 # ???
      end
      io.read(padding)

      if cDescriptor > 0 then
        raise "c descriptors unsupported"
      end
      
      #v_data = io.read((dataSize*4) - (io.pos-origin)) # dataSize is in words counts everything before the payload, too
      v_data = io.read(origin+0x100-io.pos)

      v_cDescriptor = cDescriptor > 0 ? BufferDescriptorC.unpack(io) : nil

      return IPCMessage.new(v_xDescriptors,
                            v_aDescriptors,
                            v_bDescriptors,
                            v_wDescriptors,
                            v_data,
                            v_cDescriptor,
                            v_handleDescriptor)
    end
    
    def pack
      if @xDescriptors.length > 16 then
        raise "too many buf X descriptors"
      end
      if @aDescriptors.length > 16 then
        raise "too many buf A descriptors"
      end
      if @bDescriptors.length > 16 then
        raise "too many buf B descriptors"
      end
      if @wDescriptors.length > 16 then
        raise "too many type W descriptors"
      end
      if @data.length.bit_length > 10 then
        raise "data too long"
      end
      word0 = 4 | # "IPC Version? Always 4."
              @xDescriptors.length << 16 | # "Number of buf X descriptors (each: 2 words)."
              @aDescriptors.length << 20 | # "Number of buf A descriptors (each: 3 words)."
              @bDescriptors.length << 24 | # "Number of buf B descriptors (each: 3 words)."
              @wDescriptors.length << 28 # "Number of type W descriptors (each: 3 words), never observed."

      descriptors = (@handleDescriptor ? @handleDescriptor.pack : String.new) + [@xDescriptors, @aDescriptors, @bDescriptors, @wDescriptors].map do |arr|
        arr.map do |d|
          d.pack
        end.join
      end.join

      padding = 0.chr * ((((8+descriptors.length)/16.0).ceil*16) - (8+descriptors.length))
      # doesn't like no padding?
      if padding.length == 0 then
        padding = 0.chr * 16
      end

      secondPart = @data + (@cDescriptor ? @cDescriptor.pack : String.new)

      length = (8 + # word0 and word1
                descriptors.length +
                padding.length +
                secondPart.length)/4
      
      word1 = (@forced_length || length) | # Data size, patched in later
              (@cDescriptorEnabled ? 2 : 0) << 10 | # "If set to 2, enable buf C descriptor."
              (@handleDescriptor != nil ? 1 : 0) << 31 # "Enable handle descriptor."
      # There's gotta be some fields missing in word1, right?

      forcedPadding = String.new
      if @forced_length != nil then
        if length > @forced_length then
          @data = @data[0, @data.length-(length-@forced_length)] # truncate
        else
          forcedPadding = 0.chr * 4 * (@forced_length-length)
        end
      end
      
      return [word0, word1].pack("L<L<") + descriptors + padding + secondPart + forcedPadding
    end
    
    def send_current_pid
      @handleDescriptor||= HandleDescriptor.new
      @handleDescriptor.send_current_pid
    end

    def x_descriptor(addr, size, counter)
      @xDescriptors.push BufferDescriptorX.new(addr, size, counter)
    end

    def a_descriptor(addr, size)
      @aDescriptors.push BufferDescriptorAB.new(addr, size)
    end

    def b_descriptor(addr, size)
      @bDescriptors.push BufferDescriptorAB.new(addr, size)
    end

    def w_descriptor(addr, size)
      @wDescriptors.push BufferDescriptorW.new(addr, size)
    end

    def raw_data(data)
      @data = data
      puts "data: " + data
    end

    def force_length(length)
      @forced_length = length
    end
    
    def data(cmd_id, payload = String.new)
      @data = String.new + "SFCI" + [0, cmd_id].pack("L<Q<") + payload # String.new forces encoding and I don't feel like figuring out how to do it properly
    end

    def c_descriptor(addr, size)
      @cDescriptor = BufferDescriptorC.new(addr, size)
    end

    def handle(handle)
      @handleDescriptor||= HandleDescriptor.new
      @handleDescriptor.handle handle
    end

    def get_data
      @data
    end
    
    attr_reader :handleDescriptor
  end

  class HandleDescriptor
    def initialize(send_current_pid=false,
                   handles=[],
                   b_words=[])
      @send_current_pid = send_current_pid
      @handles = handles
      @b_words = b_words
    end
  
    def send_current_pid
      @send_current_pid = true
    end

    def handle(handle)
      @handles.push handle
    end

    def pack
      if @handles.length >= 16 then
        raise "too many handles"
      end
      if @b_words.length >= 16 then
        raise "too many B-words"
      end

      # COME BACK AND CHECK THIS LATER
      # Once you're sure of yourself @misson20000,
      # edit the switchbrew page for this because I
      # think they have b_words and handles backward
      
      firstPart =  (@send_current_pid ? 1 : 0) << 0 | # "Send current PID."
                   @b_words.length << 1 | # "Number of handles."
                   @handles.length << 5 # "Number of B-words for this special descriptor."
      return [firstPart].pack("L<") + @b_words.pack("L<*") + @handles.pack("L<*") + (@send_current_pid ? 0.chr*4 : String.new)
    end

    def self.unpack(io)
      header = io.read(4).unpack("L<")[0] # might be a whole word long, not sure
      send_current_pid = header >> 0 & 0x01
      num_b_words      = header >> 1 & 0x0F
      num_handles      = header >> 5 & 0x0F
      b_words = io.read(num_b_words * 4).unpack("L<*")
      handles = io.read(num_handles * 4).unpack("L<*")
      if send_current_pid then
        io.read(4)
      end
      return HandleDescriptor.new(send_current_pid, handles, b_words)
    end

    attr_reader :handles
  end
  
  class BufferDescriptorAB
    def initialize(address, size, permissions)
      @size = size
      @addr = address
      @perm = permissions
    end

    attr_accessor :size
    attr_accessor :addr
    attr_accessor :perm
    
    def pack
      if @addr.bit_length > 38 then
        raise "addr too long"
      end
      if @size.bit_length > 35 then
        raise "size too long"
      end
      if @perm.bit_length > 3 then
        raise "permissions too long"
      end
      return [@size & 0xFFFFFFFF, # "Lower 32-bits of size."
              @addr & 0xFFFFFFFF, # "Lower 32-bits of address."
              @perm << 0 | # "Always set to 1 or 3. R/RW."
              ((@addr >> 36) & 0x7) <<  2 | # "Bit 38-36 of address."
              ((@size >> 32) & 0xF) << 24 | # "Bit 35-32 of size."
              ((@addr >> 32) & 0xF) << 28]  # "Bit 35-32 of address."
               .pack("L<L<L<")
    end

    def self.unpack(io)
      words = io.read(12).unpack("L<L<L<")
      addr = words[1] | (((words[2] >> 28) & 0xF) << 32) | (((words[2] >> 2) & 0x7) << 36)
      size = words[0] | (((words[2] >> 24) & 0xF) << 32)
      perm = words[1] & 3
      return BufferDescriptorAB.new(addr, size, perm)
    end
  end

  class BufferDescriptorC
    def initialize(address, size)
      @addr = address
      @size = size
    end

    attr_accessor :addr
    attr_accessor :size

    def pack
      if @size.bit_length > 16 then
        raise "size too long"
      end
      if @addr.bit_length > 48 then
        raise "address too high"
      end
      return [(@addr & 0x0000FFFFFFFF),
              (@addr & 0xFFFF00000000) >> 32,
              @size << 16].pack("L<L<")
    end

    def unpack(io)
      io.read(2)
    end
  end

  class BufferDescriptorX
    def initialize(address, size, counter)
      @addr = address
      @size = size
      @cntr = counter
    end

    attr_accessor :addr
    attr_accessor :size
    attr_accessor :cntr

    def counter
      @cntr
    end
    def counter=(n)
      @cntr = n
    end

    def pack
      if @addr.bit_length > 38 then
        raise "address too long"
      end
      if @size.bit_length > 16 then
        raise "size too long"
      end
      return [
        (@cntr & 0x4F) << 0 |
        ((@addr >> 36) & 0x7) << 6 | # the hecc, nintendo?! are bits 6-9 of the "counter" just gone?
        ((@cntr >>  9) & 0x7) << 9 |
        ((@addr >> 32) & 0xF) << 12 |
        ((@size >>  0) & 0xFFFF) << 16,
        @addr & 0xFFFFFFFF
      ].pack("L<L<")
    end

    def unpack(io)
      io.read(2)
    end
  end
end

class Session
  def initialize(handle)
    @handle = handle
    @buf = $dsl.malloc 0x2000
    @buf_size = 0x2000
  end

  def self.connect_service(name)
    buffer = $dsl.new Types::SessionHandle
    code = Bridges::smGetServiceHandle.call(buffer, name, name.length)
    if code.value != 0 then
      throw code
    end
    handle = buffer.deref
    buffer.free
    return self.new(handle)
  end

  def self.connect_port(name)
    buffer = $dsl.new Types::SessionHandle
    code = SVC::ConnectToPort.call(buffer, name)
    if code.value != 0 then
      throw code
    end
    handle = buffer.deref
    buffer.free
    return self.new(handle)    
  end

  def build_and_send(&block)
    send(IPC::create_message(&block))
  end
  
  def send(message)
    if message.length > @buf_size then
      @buf.free
      @buf_size = ((message.length) / 0x2000).ceil * 0x2000
      @buf = $dsl.malloc @buf_size
    end
    @buf.write(message)
    code = Bridges::sendSyncRequestWrapper.call(@handle, @buf, @buf_size)
    if code.value != 0 then
      throw code
    end
    response = @buf.read(@buf_size)
    return IPC::IPCMessage.unpack(StringIO.new(response)) # StringIO is safer than PointerIO in the event of a malformed IPC message or a bug in my parser
  end

  def close
    SVC::CloseHandle.call(@handle)
  end
  
  attr_reader :handle
  attr_reader :buf
end

class ServiceManagerPort
  def initialize(session)
    @session = session
  end

  def Initialize
    @session.build_and_send do
      force_length(0x0A)
      send_current_pid
      data(0)
    end
  end

  def GetService(name)
    if name.length > 8 then
      raise "name too long"
    end
    response = @session.build_and_send do
      force_length(0x0A)
      data(1, name + (0.chr * (8-name.length)))
    end
    responseCode = ResultCode.get(response.get_data.unpack("L<L<L<")[2])
    if responseCode == ResultCode::OK then
      return Session.new(response.handleDescriptor.handles.first)
    else
      raise responseCode
    end
  end

  def RegisterService(name, max_sessions=16, unknown_bool) # max sessions is a maybe
    @session.build_and_send do
      force_length(0x0C)
      data(2, name + (0.chr * (8-name.length)) + [max_sessions, unknown_bool].pack("L<L<"))
    end
  end

  def close
    @session.close
  end

  attr_reader :session
end

module Services
  class NVDRV_A
    def initialize
    end
  end

  class FspSrv
    def initialize(session)
      @session = session
    end

    def Initialize
      @session.build_and_send do
        force_length(0x0A)
        send_current_pid
        data(0, [1].pack("L<"))
      end
    end
    
    def close
      @session.close
    end
    
    attr_reader :session
  end
end
