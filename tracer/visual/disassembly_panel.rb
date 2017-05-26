module Tracer
  module Visual
    class DisassemblyPanel
      def initialize(visual, pg_state, debugger_dsl)
        @visual = visual
        @window = Curses::Window.new(0, 0, 0, 0)
        @window.keypad = true
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        @cursor = pg_state.pc
      end

      def redo_layout(miny, minx, maxy, maxx)
        @window.resize(maxy-miny, maxx-minx)
        @window.move(miny, minx)
        @width = maxx-minx
        @height = maxy-miny
        @x = minx
        @y = miny
        self.recenter
      end

      attr_reader :window
      attr_reader :cursor
      
      def recenter
        @start = @cursor -
                 (@height/2) * # instructions
                 4 # instruction length
      end
      
      def cursor_moved
        if @cursor > @start + (@height*4*2/3) then
          recenter
        end
        if @cursor < @start + (@height*4*1/3) then
          recenter
        end
        @visual.memviewer_panel.refresh
        refresh
      end

      def handle_key(key)
        @visual.minibuffer_panel.content = ""
        
        if @ays then
          if key == "P" then
            @pg_state.pc = @cursor
            @visual.state_change
            @ays = false
            return true
          end
        end
        @ays = false
        
        case key
        when "s"
          @debugger_dsl.step
          @visual.state_change
        when "S"
          @debugger_dsl.step_to @cursor
          @visual.state_change
        when "r"
          @debugger_dsl.rewind 1
          @visual.state_change
        when "R"
          @debugger_dsl.rewind_to @cursor
          @visual.state_change
        when Curses::KEY_UP
          @cursor-= 4
          self.cursor_moved
        when Curses::KEY_DOWN
          @cursor+= 4
          self.cursor_moved
        when "p"
          @cursor = @pg_state.pc
          self.cursor_moved
        when "P"
          @visual.minibuffer_panel.content = "Are you sure? Shift-P to move PC to cursor."
          @ays = true
        else
          return false
        end
        return true
      end
      
      def refresh
        @window.setpos(0, 0)
        @window.attron(Curses::color_pair(ColorPairs::Border))
        @window.addstr("Disassembler".ljust(@width))
        @window.attroff(Curses::color_pair(ColorPairs::Border))

        lines = []
        
        (@height-1).times do |i|
          addr = @start + (i*4)
          i = @pg_state.cs.disasm(@pg_state.uc.mem_read(addr, 4), addr).each.next

          addr_parts = [addr].pack("Q<").unpack("L<L<")
          flags = Flag.where(:mostsig_pos => addr_parts[1], :leastsig_pos => addr_parts[0]).all
          if flags.length > 0 then
            lines.push [nil, ""]
          end
          flags.each do |f|
            lines.push [nil, "      " + f.name + ":"]
          end
          
          markings = "          "
          lines.push([addr, (markings + i.mnemonic.to_s + " " + i.op_str.to_s).ljust(@width)])
          if @cursor == addr then
            @curs_y = lines.length
            @curs_x = markings.length
          end
        end

        lines.each_with_index do |line, i|
          @window.setpos(i+1, 0)
          if line[0] == @pg_state.pc then
            @window.attron(Curses::color_pair(ColorPairs::PC))
          end

          @window.addstr(line[1])
          @window.clrtoeol
          @window.attroff(Curses::color_pair(ColorPairs::PC))
        end

        @window.setpos(@curs_y, @curs_x)
        @window.refresh
      end
    end
  end
end
