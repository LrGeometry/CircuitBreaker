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
      pos = io.pos
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
        raise "bad IPC version: " + ipcVersion.to_s
      end

      v_handleDescriptor = handleDescriptor > 0 ? HandleDescriptor.unpack(io) : nil
    
      v_xDescriptors = numXDescriptors.times.map do |_|
        BufferDescriptorX.unpack(io)
      end
      v_aDescriptors = numADescriptors.times.map do |_|
        BufferDescriptorA.unpack(io)
      end
      v_bDescriptors = numBDescriptors.times.map do |_|
        BufferDescriptorB.unpack(io)
      end
      v_wDescriptors = numWDescriptors.times.map do |_|
        BufferDescriptorW.unpack(io)
      end

      io.read(((io.pos / 16.0).ceil * 16) - pos) # padding
      v_data = io.read(dataSize * 4)

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
      word1 = @data.size |
              (@cDescriptorEnabled ? 2 : 0) << 10 | # "If set to 2, enable buf C descriptor."
              (@handleDescriptor != nil ? 1 : 0) << 31 # "Enable handle descriptor."
      # There's gotta be some fields missing in word1, right?

      firstPart = [word0, word1].pack("L<L<") + (@handleDescriptor ? @handleDescriptor.pack : String.new) + [@xDescriptors, @aDescriptors, @bDescriptors, @wDescriptors].map do |arr|
        arr.map do |d|
          d.pack
        end.join
      end.join

      padding = 0.chr * (((firstPart.length/16.0).ceil)*16 - firstPart.length)

      secondPart = @data + (@cDescriptor ? @cDescriptor.pack : String.new)
      
      return firstPart + padding + secondPart
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

    def data(data)
      @data = data
      puts "data: " + data
    end

    def c_descriptor(addr, size)
      @cDescriptor = BufferDescriptorC.new(addr, size)
    end

    def handle(handle)
      @handleDescriptor||= HandleDescriptor.new
      @handleDescriptor.handle handle
    end
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
      firstPart =  (@send_current_pid ? 1 : 0) << 0 | # "Send current PID."
                   @handles.length << 1 | # "Number of handles."
                   @b_words.length << 5 # "Number of B-words for this special descriptor."
      return [firstPart].pack("L<") + @handles.pack("L<*") + @b_words.pack("L<*")
    end

    def self.unpack(io)
      header = io.read(1).unpack("C")[0] # might be a whole word long, not sure
      send_current_pid = header >> 0 & 0x01
      num_handles      = header >> 1 & 0x0F
      num_b_words      = header >> 5 & 0x0F
      handles = io.read(num_handles * 4).unpack("L<*")
      b_words = io.read(num_b_words * 4).unpack("L<*")
      return HandleDescriptor.new(send_current_pid, handles, b_words)
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
        io.read(3)
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
end

class Session
  def initialize(handle)
    @handle = handle
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

  def send(message)
    return Bridges::sendSyncRequestWrapper(@handle, message, message.length)
  end
  
  attr_reader :handle
end

module Services
  class NVDRV_A
    def initialize
    end
  end
end
