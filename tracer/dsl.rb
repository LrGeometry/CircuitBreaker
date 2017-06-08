module Tracer
  DEBUGGER_PRY_OPTIONS = {
    :quiet => true,
    :prompt => [
      proc do |target_self, nest_level, pry|
        "[#{pry.input_array.size}] tracer debugger#{nest_level.zero? ? "" : ":" + nest_level.to_s}> "
      end,
      proc do |target_self, nest_level, pry|
        "[#{pry.input_array.size}] tracer debugger#{nest_level.zero? ? "" : ":" + nest_level.to_s}* "
      end
    ]
  }
  
  class DSL < SwitchDSL
    def initialize(pg_state)
      super()
      @pg_state = pg_state
    end
    
    attr_reader :pg_state
    
    def uc
      pg_state.uc
    end
    
    def read(pointer, offset, length, &block)
      uc.mem_read(pointer.to_i+offset, length)
    end

    def write(pointer, offset, data)
      uc.mem_write(pointer.to_i+offset, data)
      pg_state.trace_state.dirty(pg_state, pointer.to_i+offset, data.length)
    end    

    def memory_permissions(pointer)
      parts = [pointer.to_i].pack("Q<").unpack("L<L<")
      mb = MappingBlock.where do
        mostsig_offset <= parts[1]
      end.where do
        leastsig_offset <= parts[0]
      end.where do
        mostsig_endpos >= parts[1]
      end.where do
        leastsig_endpos < parts[0]
      end.first
      mb ? mb.perms : 0
    end
    
    def mref(addr)
      main_addr + addr
    end

    def malloc(size)
      make_pointer(@pg_state.alloc.malloc(size))
    end

    def free(pointer)
      @pg_state.alloc.free(pointer.value)
      nil
    end

    def _enter_debugger(fiber)
      dsl = @pg_state.debugger_dsl = DebuggerDSL.new(@pg_state, fiber)
      bind.local_variables.each do |var|
        dsl.bind.local_variable_set(var, bind.local_variable_get(var))
      end
      begin
        yield dsl, dsl.bind
        if fiber.alive? then
          fiber.resume({:stop => true})
          raise "quit debugger during execution"
        end
      ensure
        @pg_state.debugger_dsl = nil
        dsl.bind.local_variables.each do |var|
          bind.local_variable_set(var, dsl.bind.local_variable_get(var))
        end
      end
    end
    
    def call(func_ptr, int_args, registers, float_args)
      int_args.each_with_index do |arg, i|
        uc.reg_write(Unicorn::UC_ARM64_REG_X0 + i, arg)
      end
      uc.reg_write(Unicorn::UC_ARM64_REG_SP, sp.to_i)
      uc.reg_write(Unicorn::UC_ARM64_REG_LR, Tracer::RETURN_VECTOR)
      fiber = @pg_state.emu_start(func_ptr.value, Tracer::RETURN_VECTOR + 4)
      _enter_debugger(fiber) do |debugger, bind|
        response = fiber.resume({})
        if response != :reached_return_vector then
          debugger.show_state
          Pry.start(bind, DEBUGGER_PRY_OPTIONS)
        end
      end
      return uc.reg_read(Unicorn::UC_ARM64_REG_X0)
    end
    
    def start(func_ptr, int_args, registers, float_args)
      int_args.each_with_index do |arg, i|
        uc.reg_write(Unicorn::UC_ARM64_REG_X0 + i, arg)
      end
      uc.reg_write(Unicorn::UC_ARM64_REG_SP, sp.to_i)
      uc.reg_write(Unicorn::UC_ARM64_REG_LR, Tracer::RETURN_VECTOR)
      fiber = @pg_state.emu_start(func_ptr.value, Tracer::RETURN_VECTOR + 4)
      _enter_debugger(fiber) do |debugger, bind|
        debugger.show_state
        Pry.start(bind, DEBUGGER_PRY_OPTIONS)
      end
      return uc.reg_read(Unicorn::UC_ARM64_REG_X0)
    end

    def save_state
      state = pg_state.trace_state.create_child(pg_state)
      pg_state.load_state(state)
      return state
    end

    def load_state(s)
      current = pg_state.trace_state
      pg_state.load_state(s)
      return current
    end

    def base_state
      TraceState[0]
    end

    def current_state
      pg_state.trace_state
    end
    
    def clean_state
      pg_state.load_state(pg_state.trace_state)
      return pg_state.trace_state
    end
    
    def temp_flag(name, pos=nil)
      if pos == nil then
        pos = @pg_state.pc
      end
      @pg_state.add_temp_flag TempFlag.new(name, pos.to_i)
    end

    def flag(name, pos=nil)
      if pos == nil then
        pos = @pg_state.pc
      end
      flag = Flag.new
      flag.position = pos.to_i
      flag.name = name
      flag.save
      return flag
    end
    
    def method_missing(sym, *args, &block)
      flag = @pg_state.find_flag_by_name(sym.to_s)
      if flag then
        return make_pointer(flag.position)
      else
        super(sym, *args, &block)
      end
    end

    def respond_to?(sym)
      if super(sym) then
        return true
      end
      
      flag = @pg_state.find_flag_by_name(sym.to_s)
      if flag then
        return true
      else
        return false
      end
    end

    def arb_reads_safe
      return true
    end
  end
end

class Pointer
  def to_mref
    "mref(0x" + (@value - @switch.main_addr.value).to_s(16) + ")"
  end
end
