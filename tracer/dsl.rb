module Tracer  
  class DSL < SwitchDSL
    def initialize(pg_state)
      super()
      @pg_state = pg_state
      uc.mem_map(RETURN_VECTOR, 0x1000, 5)
      uc.mem_write(RETURN_VECTOR, [0xd503201f].pack("Q<"))
      uc.reg_write(Unicorn::UC_ARM64_REG_SP, Flag[:name => "sp"].position)
      uc.reg_write(Unicorn::UC_ARM64_REG_TPIDRRO_EL0, Flag[:name => "tls"].position)
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
      make_pointer(@pg_state.alloc.malloc(size))
    end

    def free(pointer)
      @pg_state.alloc.free(pointer.value)
      nil
    end

    def call(func_ptr, int_args, registers, float_args)
      int_args.each_with_index do |arg, i|
        uc.reg_write(Unicorn::UC_ARM64_REG_X0 + i, arg)
      end
      uc.reg_write(Unicorn::UC_ARM64_REG_LR, Tracer::RETURN_VECTOR)
      uc.emu_start(func_ptr.value, Tracer::RETURN_VECTOR+4)
      return uc.reg_read(Unicorn::UC_ARM64_REG_X0)
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
