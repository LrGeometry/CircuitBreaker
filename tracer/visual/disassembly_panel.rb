require "word_wrap"

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
        follow = @cursor == @pg_state.pc
        case key
        when "s"
          @debugger_dsl.step
          @visual.state_change
        when "S"
          @debugger_dsl.step_to @cursor
          @visual.state_change
        when "F"
          @debugger_dsl.step_to @debugger_dsl.x30
        when "r"
          @debugger_dsl.rewind 1
          @visual.state_change
        when "R"
          @debugger_dsl.rewind_to @cursor
          @visual.state_change
        when Curses::KEY_UP
          follow = false
          @cursor-= 4
          self.cursor_moved
        when Curses::KEY_DOWN
          follow = false
          @cursor+= 4
          self.cursor_moved
        when "p"
          follow = false
          @cursor = @pg_state.pc
          self.cursor_moved
        when "P"
          @visual.minibuffer_panel.are_you_sure("Are you sure? Shift-P to move PC to cursor.", ["P"]) do |result|
            if result then
              @pg_state.pc = @cursor
              @visual.state_change
            end
          end
        when ";"
          parts = [@cursor].pack("Q<").unpack("L<L<")
          comment = Comment[:mostsig_pos => parts[1], :leastsig_pos => parts[0]]
          if comment == nil then
            comment = Comment.create(:mostsig_pos => parts[1], :leastsig_pos => parts[0], :content => "")
          end
          @visual.minibuffer_panel.edit_comment(comment)
        when "f"
          parts = [@cursor].pack("Q<").unpack("L<L<")
          flag = Flag[:mostsig_pos => parts[1], :leastsig_pos => parts[0]]
          if flag == nil then
            flag = Flag.new
            flag.content = "lbl." + @cursor.to_s(16)
            flag.position = @cursor
          end
          @visual.minibuffer_panel.edit_flag(flag)
        else
          return false
        end
        if follow then
          @cursor = @pg_state.pc
          self.cursor_moved
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
          lines.push([addr, (markings + i.mnemonic.to_s + " " + i.op_str.to_s), markings.length])
        end

        comment_col = lines.map do |line|
          line[1].length
        end.max + 1

        lines.each_with_index do |l, i|
          if l[0] then
            addr_parts = l.pack("Q<").unpack("L<L<")
            comment = Comment[:mostsig_pos => addr_parts[1], :leastsig_pos => addr_parts[0]]
            if comment then
              parts = WordWrap.ww(comment.content, @width-comment_col-2).split("\n")
              l[1] = l[1].ljust(comment_col) + "; " + (parts.length > 0 ? parts[0] : comment.content)
              parts.drop(1).reverse.each do |part|
                lines.insert(i+1, [nil, (" " * comment_col) + "; " + part])
              end
            end
            if @cursor == l[0] then
              @curs_y = i+1
              @curs_x = l[2]
            end
          end
        end
        
        lines.each_with_index do |line, i|
          @window.setpos(i+1, 0)
          if line[0] == @pg_state.pc then
            @window.attron(Curses::color_pair(ColorPairs::PC))
          end

          @window.addstr(line[1].ljust(@width))
          @window.clrtoeol
          @window.attroff(Curses::color_pair(ColorPairs::PC))
        end

        @window.setpos(@curs_y, @curs_x)
        @window.refresh
      end
    end
  end
end
