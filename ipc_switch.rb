module IPC
  def self.create_message(code, &block)
    dsl = IPC::DSLBuilder.new(code)
    dsl.instance_exec(&block)
    return dsl.to_s
  end

  class DSLBuilder
    def initialize(code)
      @code = code
      @normal_params = String.new
      @translate_params = String.new
    end
    
    def to_s
      if @translate_params.length > (2**6) then
        raise "translate parameters too long"
      end
      if @normal_params.length > (2**6) then
        raise "normal parameters too long"
      end
      header_code = ((@translate_params.length / 4) << 0) |
                    ((@normal_params.length / 4) << 6) |
                    (@code << 16)
      return [header_code].pack("L<") + @translate_params + @normal_params
    end

    def param(string)
      @normal_params+= string
    end
    
    def shared_handles(array)
      @translate_params+= [Util.Desc_SharedHandles(array.size)].pack("L<")
      @translate_params+= array.map do |h|
        [h].pack("L<")
      end.join
    end
    
    def move_handles(array)
      @translate_params+= [Util.Desc_MoveHandles(array.size)].pack("L<")
      @translate_params+= array.map do |h|
        [h].pack("L<")
      end.join
    end

    def current_process_handle
      @translate_params+= [Util.Desc_CurProcessHandle].pack("L<")
      @translate_params+= [0].pack("L<")
    end
    
    # copies data to the specified static buffer in the receiver
    # IS THIS CORRECT FOR THE SWITCH, WHAT WITH 64-BIT POINTERS?!?
    # experiment here!
    def static_buffer(pointer, size, index)
      @translate_params+= [Util.Desc_StaticBuffer(size, index)].pack("L<")
      @translate_params+= [pointer.value].pack("L<")
    end
  end
  
  module Util
    class << self
      def Desc_SharedHandles(num)
        return (num - 1) << 26
      end
      
      def Desc_MoveHandles(num)
        return ((num - 1) << 26) | 0x10
      end
      
      def Desc_CurProcessHandle
        return 0x20
      end
      
      def Desc_StaticBuffer(size, buffer_id)
        return (size << 14) | ((buffer_id & 0xF) << 10) | 0x2
      end
      
      def Desc_PXIBuffer(size, buffer_id, is_read_only)
        type = is_read_only ? 0x6 : 0x4
        return (size << 8) | ((buffer_id & 0xF) << 4) | type
      end
      
      # 0: none
      # 1: R
      # 2: W
      # 3: RW
      def Desc_Buffer(size, rights)
        return (size << 4) | 0x8 | rights
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

  attr_reader :handle
end

module Services
  class NVDRV_A
    def initialize
    end
  end
end
