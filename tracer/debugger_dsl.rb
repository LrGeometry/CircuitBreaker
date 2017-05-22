module Tracer
  class DebuggerDSL < Tracer::DSL
    def initialize(pg_state, fiber)
      super(pg_state)
      @fiber = fiber
      @state = self.save_state
      @registers_dsl = RegistersDSL.new(pg_state)
      @visual_active = false
      self.load_state(@state)
    end

    def visual
      require_relative "visual.rb"
      @visual_active = true
      begin
        (@visual_mode||= Visual::VisualMode.new(@pg_state, self)).open
      ensure
        @visual_active = false
      end
    end
    
    def rewind(num=1)
      target_count = pg_state.instruction_count - num
      if(target_count < @state.instruction_count) then
        raise "can't rewind that far!"
      end
      self.load_state(@state)
      self.step(target_count - pg_state.instruction_count)
    end

    def rewind_to(addr)
      count = pg_state.instruction_count
      self.load_state(@state)
      if(pg_state.pc == addr) then
        return
      end
      
      ultimate_state = nil
      while pg_state.instruction_count < count do
        self.step_to(addr, true)
        if pg_state.instruction_count >= count then
          break
        end
        if ultimate_state then
          ultimate_state.destroy
        end
        ultimate_state = @state.create_child(pg_state)
      end
      if !ultimate_state then
        raise "target never hit"
      end
      self.load_state(ultimate_state)
      show_state
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
      if @visual_active then
        return
      end
      
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

    def step_to(addr, inhibit_show_state=false)
      reason = @fiber.resume({:break_at => addr})
      if !inhibit_show_state then
        show_state
      end
    end

    def continue
      @fiber.resume({:instruction_count => -1})
    end
    
    def pc
      make_pointer(@pg_state.pc)
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
