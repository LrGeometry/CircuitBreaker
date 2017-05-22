require "curses"

module Tracer
  module Visual
    module ColorPairs
      PC = 1
    end
    
    class StatePanel
      def initialize(visual, window, pg_state, debugger_dsl)
        @visual = visual
        @window = window
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        self.resize
      end

      def resize
        @width = @window.maxx-@window.begx-2
        @height = @window.maxy-@window.begy-2
        self.refresh
      end
      
      def refresh
        @window.box("|", "-")
        @window.setpos(0, 1)
        @window.addstr("CPU State")

        entries = (0..30).each.map do |r_num|
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
          (pair[0] + ": ").rjust(5) + @debugger_dsl.show_addr(pair[1]).ljust(20)
        end
        
        max_length = entries.map do |e|
          e.length
        end.max

        columns = (@width/(max_length+1)).floor
        y = 1
        entries.each_slice(columns) do |row|
          spacing = ((@width - (columns * max_length))/columns).floor
          @window.setpos(y, 1)
          @window.addstr(row.join(" " * spacing))
          y+= 1
        end
        
        @window.refresh
      end
    end

    class DisassemblyPanel
      def initialize(visual, window, pg_state, debugger_dsl)
        @visual = visual
        @window = window
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        self.resize
      end

      def resize
        @width = @window.maxx-@window.begx-2
        @height = @window.maxy-@window.begy-2
        @window.setpos(0, 15)
        @window.addstr(@height.inspect)
        self.recenter
        self.refresh
      end

      def recenter
        @start = @visual.cursor -
                 (@height/2) * # instructions
                 4 # instruction length

      end
      
      def cursor_moved
        if @visual.cursor > @start + (@height*4*2/3) then
          recenter
        end
        if @visual.cursor < @start + (@height*4*1/3) then
          recenter
        end
        refresh
      end
      
      def refresh
        @height.times do |i|
          @window.setpos(i+1, 1)
          addr = @start + (i*4)
          i = @pg_state.cs.disasm(@pg_state.uc.mem_read(addr, 4), addr).each.next
          if addr == @pg_state.pc then
            @window.attron(Curses::color_pair(ColorPairs::PC))
          end
          markings = "    "
          @window.addstr((markings + (@visual.cursor == addr ? " => " : "    ") + i.mnemonic.to_s + " " + i.op_str.to_s).ljust(@width))
          @window.clrtoeol
          @window.attroff(Curses::color_pair(ColorPairs::PC))
        end

        @window.box("|", "-")
        @window.setpos(0, 1)
        @window.addstr("Disassembly")
        
        @window.refresh
      end
    end
    
    class VisualMode
      def initialize(pg_state, debugger_dsl)
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        @cursor = pg_state.pc
      end

      attr_accessor :cursor
      
      def open
        begin
          Curses.init_screen
          Curses.start_color
          Curses.init_pair(ColorPairs::PC, Curses::COLOR_BLACK, Curses::COLOR_YELLOW)
          Curses.nonl
          Curses.cbreak
          Curses.noecho
          
          @running = true
          @screen = Curses.stdscr

          @state_panel_window = Curses::Window.new(@screen.maxy, 28*2, 0, 0)
          @disassembly_panel_window = Curses::Window.new(@screen.maxy, 80, 0, 28*2)

          @screen.keypad = true
          @disassembly_panel_window.keypad = true
          
          @state_panel = StatePanel.new(self, @state_panel_window, @pg_state, @debugger_dsl)
          @disassembly_panel = DisassemblyPanel.new(self, @disassembly_panel_window, @pg_state, @debugger_dsl)

          while @running do
            chr = @disassembly_panel_window.getch
            case chr
            when "q"
              @running = false
            when "s"
              @debugger_dsl.step
              @state_panel.refresh
              @disassembly_panel.refresh
            when "S"
              @debugger_dsl.step_to @cursor
              @state_panel.refresh
              @disassembly_panel.refresh              
            when "r"
              @debugger_dsl.rewind 1
              @state_panel.refresh
              @disassembly_panel.refresh
            when "R"
              @debugger_dsl.rewind_to @cursor
              @state_panel.refresh
              @disassembly_panel.refresh              
            when Curses::KEY_UP
              @cursor-= 4
              @disassembly_panel.cursor_moved
            when Curses::KEY_DOWN
              @cursor+= 4
              @disassembly_panel.cursor_moved
            end
          end
        ensure
          Curses.close_screen
        end
      end
    end
  end
end
