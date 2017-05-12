class Program
  def initialize(switch, fields, buffer, operations)
    @switch = switch
    @fields = fields
    @buffer_content = buffer
    @buffer = @switch.malloc buffer.length
    @buffer.write buffer
    @operations = operations
  end

  attr_reader :buffer
  attr_reader :operations
end

class ProgramBuilder
  def initialize(switch)
    @switch = switch
    @static_fields = nil
    @static_buffer = nil
    @operations = []
  end

  class StaticField
    def initialize(symbol, initial_value, location)
      @symbol = symbol
      @initial_value = initial_value
      @location = location
    end

    def finalize(fields)
    end
    
    attr_reader :symbol
    attr_reader :initial_value
    attr_reader :location
  end

  class StaticReference
    def initialize(symbol, target, location)
      @symbol = symbol
      @target = target
      @location = location
    end

    def finalize(fields)
      @initial_value = fields[@target].location
    end
    
    attr_reader :symbol
    attr_reader :initial_value
    attr_reader :target
    attr_reader :location
  end
  
  class StaticBuilder
    def initialize
      @size = 0
      @fields = {}
      @field_sequence = []
    end

    def field(name, value)
      field = StaticField.new(name, value, @field_sequence.size * 8)
      @fields[name] = field
      @field_sequence.push field
    end

    def constant(name, value) # same as field but different semantics
      field(name, value)
    end
    
    def reference(name, target)
      field = StaticReference.new(name, target, @field_sequence.size * 8)
      @fields[name] = field
      @field_sequence.push field
    end
    
    def finalize
      @fields.each do |f|
        f.finalize(@fields) # resolve references to initial values
      end
      @buffer = @fields.map do |f|
        f.initial_value
      end.pack("Q<*")
    end
    
    def get_initial_buffer
      @buffer
    end

    def get_field_map
      @fields
    end
  end
  
  def statics(&block)
    builder = StaticBuilder.new
    builder.instance_exec &block
    builder.finalize
    @static_fields = builder.get_field_map
    @static_buffer = builder.get_initial_buffer
  end

  class CallOperation
    def initialize(bridge, arg_fields, ret_field)
      @bridge = bridge
      @arg_fields = arg_fields
      @ret_field = ret_field
    end

    attr_reader :bridge
    attr_reader :arg_fields
    attr_reader :ret_field
    
    def to_h
      {:type => :call,
       :func_ptr => bridge.to_ptr.to_switch,
       :arg_fields => arg_fields.map do |f|
         (@static_buffer + f.location).to_switch
       end,
       :ret_field => (@static_buffer + ret_field.location).to_switch}
    end

    def type
      :call
    end
  end
  
  def call(bridge, arg_fields, ret_field)
    @operations.push CallOperation.new(bridge, arg_fields.map do |symbol|
                                         @static_fields[symbol]
                                       end, @static_fields[ret_field])
  end

  def to_program
    Program.new(@static_fields, @static_buffer, @operations)
  end
end

# monkey patching ftw!
class SwitchDSL
  def create_program(&block)
    builder = ProgramBuilder.new
    builder.instance_exec &block
    return builder.to_program
  end
end
