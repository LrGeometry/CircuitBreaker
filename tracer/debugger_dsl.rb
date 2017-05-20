module Tracer
  class DebuggerDSL < Tracer::DSL
    def initialize(pg_state, fiber)
      super(pg_state)
      @fiber = fiber
      @registers_dsl = RegistersDSL.new(pg_state)
    end

    def show_addr(addr)
      flag = @pg_state.find_flag_by_before(addr)
      if(flag && (addr-flag.position) < 0x400) then
        return flag.name + "+0x" + (addr-flag.position).to_s(16).rjust(4, "0")
      else
        return "0x" + addr.to_s(16).rjust(16, "0")
      end
    end
    
    def show_state
      puts
      (0..30).each.map do |r_num|
        reg_id = Unicorn::UC_ARM64_REG_X0 + r_num
        if r_num == 29 then
          reg_id = Unicorn::UC_ARM64_REG_X29
        elsif r_num == 30 then
          reg_id = Unicorn::UC_ARM64_REG_X30
        end
        val = @pg_state.uc.reg_read(reg_id)
        ["X" + r_num.to_s, val]
      end.concat(
        {"SP" => Unicorn::UC_ARM64_REG_SP,
         "PC" => Unicorn::UC_ARM64_REG_PC}.each_pair.map do |name, id|
          [name, @pg_state.uc.reg_read(id)]
        end
      ).map do |pair|
        (pair[0] + ": ").rjust(5) + show_addr(pair[1]).ljust(20)
      end.each_slice(3) do |row|
        puts "  " + row.join("    ")
      end

      puts
      
      @pg_state.cs.disasm(@pg_state.uc.mem_read(@pg_state.pc-8, 20), @pg_state.pc-8).each do |i|
        puts (i.address == @pg_state.pc ? "=> " : "   ") + show_addr(i.address).rjust(20) + ": " + i.mnemonic + " " + i.op_str
      end
      nil
    end

    def p
      show_state
    end
    
    def s(n=1)
      step(n)
    end

    def step(n=1)
      @fiber.resume({:instruction_count => n})
      show_state
    end

    def continue
      @fiber.resume({:instruction_count => -1})
    end
    
    def pc
      @dsl.make_pointer(@pg_state.pc)
    end

    (0..28).each do |num|
      define_method(("x" + num.to_s).to_sym) do |val=nil|
        if val != nil then
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0 + num, val.to_i)
          show_state
        else
          @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X0 + num)
        end
      end
    end

    def x29(val=nil)
      if val != nil then
        @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X29, val.to_i)
        show_state
      else
        @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X29)
      end
    end
    
    def x30(val=nil)
      if val != nil then
        @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X30, val.to_i)
        show_state
      else
        @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X30)
      end
    end

    def x
      @registers_dsl
    end

    def sp
      @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_SP)
    end
    def sp=(val)
      @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_SP, val.to_i)
      show_state
    end

    class RegistersDSL
      def initialize(pg_state)
        @pg_state = pg_state
      end

      def reg_id(num)
        if num <= 28 then
          return Unicorn::UC_ARM64_REG_X0 + num
        elsif num == 29
          return Unicorn::UC_ARM64_REG_X29
        elsif num == 30
          return Unicorn::UC_ARM64_REG_X30
        else
          raise "no such register"
        end
      end
      
      def [](num)
        @pg_state.uc.reg_read(reg_id(num))
      end

      def []=(num, val)
        @pg_state.uc.reg_write(reg_id(num), val.to_i)
        @pg_state.debugger_dsl.show_state
      end
    end
  end
end
