module Tracer
  module Visual
    class StatePanel < ::Visual::Panel
      def initialize(visual, pg_state, debugger_dsl)
        super()
        @visual = visual
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
      end

      def redo_layout(miny, minx, maxy, maxx, parent=nil)
        super
        self.refresh
      end
      
      def refresh
        @window.clear
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

        @window.setpos(0, 0)
        @window.attron(Curses::color_pair(ColorPairs::Border))
        @window.addstr("State Viewer".ljust(@width))
        @window.attroff(Curses::color_pair(ColorPairs::Border))
        
        columns = [(@width/(max_length+1)).floor, 1].max
        y = 1
        entries.each_slice(columns) do |row|
          spacing = [((@width - (columns * max_length))/columns).floor, 0].max
          @window.setpos(y, 0)
          @window.addstr(row.join(" " * spacing))
          y+= 1
        end
        
        @window.refresh
      end
    end
  end
end
