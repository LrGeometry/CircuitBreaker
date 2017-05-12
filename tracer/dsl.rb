module Tracer
  RETURN_VECTOR = 0xDEADBEEF11110000
  
  class DSL < SwitchDSL
    def initialize(pg_state)
      @pg_state = pg_state
      uc.mem_map(RETURN_VECTOR, 0x1000)
    end
    
    attr_reader :pg_state
    
    def uc
      pg_state.uc
    end
    
    def read(pointer, offset, length, &block)
      uc.mem_read(pointer.value+offset, length)
    end

    def write(pointer, offset, data)
      uc.mem_write(pointer.value+offset, data)
    end    
    
    def mref(addr)
      main_addr + addr
    end

    def malloc(size)
      raise "nyi"
    end

    def free(pointer)
      raise "nyi"
    end

    def call(func_ptr, int_args, registers, float_args)
      int_args.each_with_index do |arg, i|
        uc.reg_write(Unicorn::UC_ARM64_REG_X0 + i, arg)
      end
      uc.reg_write(Unicorn::UC_ARM64_REG_LR, Tracer::RETURN_VECTOR)
      binding.pry
      uc.emu_start(func_ptr.value, Tracer::RETURN_VECTOR)
    end
    
    def new_trace
      pg_state.trace_state.create_child.load_state(pg_state)
      puts "Loaded trace state " + pg_state.trace_state.id.to_s
    end    
    
    def method_missing(sym, *args)
      flag = Flag[:name => sym.to_s]
      if flag then
        return make_pointer(flag.position)
      else
        super(sym, *args)
      end
    end
  end
end
