class Type
  def pointer
    @pointerType||= PointerType.new(self)
  end
end

class PointerType < Type
  def initialize(pointedType)
    super(pointedType.name + "*", 8)
    @pointedType = pointedType
  end
  
  def decode(switch, val)
    Pointer.new(switch, val.unpack("Q<")[0], @pointedType)
  end

  def encode(val)
    [val.value].pack("Q<").unpack("L<L<")
  end

  def is_pointer
    true
  end

  def is_supported_return_type?
    true
  end

  def argument_mode
    :integer
  end

  def coerce_to_argument(switch, value, finalizer_list)
    if @pointedType == Types::Char && value.is_a?(String) then
      buf = Pointer.from_switch(switch, switch.command("malloc", {:length => value.length + 1})["address"])
      buf.cast! Types::Char
      buf.write(value)
      buf[value.length] = 0
      finalizer_list.push(proc do
                            buf.free
                          end)
      return encode(buf)
    end
    if value.is_a? Array then
      buf = Pointer.from_switch(switch,
                                switch.command("malloc",
                                               {:length => value.length * @pointedType.size})["address"])
      buf.cast! @pointedType
      value.each_with_index do |item, i|
        buf[i] = item
      end
      finalizer_list.push(proc do
                            value.length.times do |i|
                              value[i] = buf[i]
                            end
                            buf.free
                          end)
      return encode(buf)
    end
    if value == nil then
      return encode(Pointer.new(switch, 0))
    end
    encode(value)
  end

  def coerce_from_return(switch, pair)
    Pointer.from_switch(switch, pair).cast!(@pointedType)
  end
end

class Pointer
  def initialize(switch, value, targetType = Types::Void)
    @switch = switch
    @value = value
    @targetType = targetType
  end

  attr_accessor :value
  
  def self.from_switch(switch, arr)
    return self.new(switch, arr.pack("L<L<").unpack("Q<")[0])
  end
  
  def to_switch(offset=0)
    [@value + offset].pack("Q<").unpack("L<L<")
  end

  def read(length, offset=0)
     @switch.command("read", {:address => to_switch(offset), :length => length})
  end

  def write(data, offset=0)
    @switch.command("write", {:address => to_switch(offset), :payload => Base64.strict_encode64(data)})
    nil
  end

  def cast(targetType)
    return Pointer.new(@switch, @value, targetType)
  end

  def cast!(targetType)
    @targetType = targetType
    return self
  end
  
  def [](i)
    if @targetType.size > 0 then
      return @targetType.decode(@switch, read(@targetType.size, i * @targetType.size))
    else
      raise "Cannot index void*"
    end
  end

  def []=(i, val)
    if @targetType != nil then
      write(@targetType.encode(val), i * @targetType.size)
    else
      raise "Cannot index void*"
    end
  end

  def member_ptr(memberName)
    if @targetType.is_a? StructType then
      field = @targetType.fields.find do |f|
        f.name == memberName
      end
      if !field then
        raise "No such field in target " + @targetType.inspect
      end
      return Pointer.new(@switch, @value + field.offset, field.type)
    else
      raise "Not a struct pointer"
    end
  end

  def arrow(memberName)
    member_ptr(memberName).deref
  end

  def deref
    self[0]
  end
  
  # create function pointer
  def bridge(return_type, *argument_types)
    return FunctionPointer.new(@switch, self, return_type, argument_types)
  end

  def to_i
    @value
  end
  
  def +(off)
    return Pointer.new(@switch, @value + (off * (@targetType.size == 0 ? 1 : @targetType.size)), @targetType)
  end

  def -(off)
    if off.is_a? Pointer then
      return @value - off.value
    else
      return self + (-off)
    end
  end

  def inspect
    @targetType.name + "* = 0x" + @value.to_s(16)
  end

  def is_null_ptr?
    @value == 0
  end

  def free
    @switch.command("free", {:address => self.to_switch})
    nil
  end
end
