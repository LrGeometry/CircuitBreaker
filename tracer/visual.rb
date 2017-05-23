require "curses"

module Tracer
  module Visual
    module ColorPairs
      PC = 1
      Border = 2
    end
    
    class StatePanel
      def initialize(visual, pg_state, debugger_dsl)
        @visual = visual
        @window = Curses::Window.new(0, 0, 0, 0)
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
      end

      def redo_layout(miny, minx, maxy, maxx)
        @window.resize(maxy-miny, maxx-minx)
        @window.move(miny, minx)
        @width = maxx-minx
        @height = maxy-miny
      end
      
      def refresh
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
        
        columns = (@width/(max_length+1)).floor
        y = 1
        entries.each_slice(columns) do |row|
          spacing = ((@width - (columns * max_length))/columns).floor
          @window.setpos(y, 0)
          @window.addstr(row.join(" " * spacing))
          y+= 1
        end
        
        @window.refresh
      end
    end

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
        refresh
      end

      def handle_key(key)
        @visual.minibuffer_panel.content = ""
        
        if @ays then
          if key == "P" then
            @pg_state.pc = @cursor
            @visual.state_panel.refresh
            self.refresh
            @ays = false
            return true
          end
        end
        @ays = false
        
        case key
        when "s"
          @debugger_dsl.step
          @visual.state_panel.refresh
          self.refresh
        when "S"
          @debugger_dsl.step_to @cursor
          @visual.state_panel.refresh
          self.refresh              
        when "r"
          @debugger_dsl.rewind 1
          @visual.state_panel.refresh
          self.refresh
        when "R"
          @debugger_dsl.rewind_to @cursor
          @visual.state_panel.refresh
          self.refresh
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
        
        (@height-1).times do |i|
          @window.setpos(i+1, 0)
          addr = @start + (i*4)
          i = @pg_state.cs.disasm(@pg_state.uc.mem_read(addr, 4), addr).each.next
          if addr == @pg_state.pc then
            @window.attron(Curses::color_pair(ColorPairs::PC))
          end
          markings = "    "
          @window.addstr((markings + (@cursor == addr ? " => " : "    ") + i.mnemonic.to_s + " " + i.op_str.to_s).ljust(@width))
          @window.clrtoeol
          @window.attroff(Curses::color_pair(ColorPairs::PC))
        end
        
        @window.refresh
      end
    end

    class BorderPanel
      def initialize(dir)
        @window = Curses::Window.new(0, 0, 0, 0)
        @dir = dir
      end

      def redo_layout(miny, minx, maxy, maxx)
        @window.resize(maxy-miny, maxx-minx)
        @window.move(miny, minx)

        @window.attron(Curses::color_pair(ColorPairs::Border))
        (miny..maxy).each do |y|
          @window.setpos(y, 0)
          @window.addstr({:horiz => "-", :vert => "|"}[@dir] * (maxx-minx))
        end
        @window.attroff(Curses::color_pair(ColorPairs::Border))
      end

      def refresh
        @window.refresh
      end
    end

    class MiniBufferPanel
      def initialize(visual)
        @window = Curses::Window.new(0, 0, 0, 0)
      end

      def redo_layout(miny, minx, maxy, maxx)
        @window.resize(maxy-miny, maxx-minx)
        @window.move(miny, minx)
        @width = maxx-minx
      end

      def content=(c)
        @content = c
        self.refresh
      end
      
      def refresh
        @window.setpos(0, 0)
        @window.addstr((@content || "").ljust(@width))
        @window.refresh
      end
    end
    
    class BSPLayout
      def initialize(options, a, b)
        @options = options
        if !options[:dir] then
          raise "no direction specified"
        end

        @mode = nil
        if @options[:fixed_item] then
          if @mode != nil then
            raise "multiple mode specifiers"
          end
          @mode = :fixed
        end
        if @mode == nil then
          raise "must specify a mode"
        end
        
        @a = a
        @b = b
        @border = BorderPanel.new({:horiz => :vert, :vert => :horiz}[options[:dir]])
      end

      def redo_layout(miny, minx, maxy, maxx)
        if @options[:dir] == :vert then
          if @mode == :fixed then
            if @options[:fixed_item] == :a then
              @a.redo_layout(miny, minx, miny+@options[:fixed_size], maxx)
              @b.redo_layout(miny+@options[:fixed_size]+1, minx, maxy, maxx)
              @border.redo_layout(miny+@options[:fixed_size], minx, miny+@options[:fixed_size]+1, maxx)
            else
              @a.redo_layout(miny, minx, maxy-@options[:fixed_size]-1, maxx)
              @b.redo_layout(maxy-@options[:fixed_size], minx, maxy, maxx)
              @border.redo_layout(maxy-@options[:fixed_size]-1, minx, maxy-@options[:fixed_size], maxx)
            end
          end
        elsif @options[:dir] == :horiz then
          if @mode == :fixed then
            if @options[:fixed_item] == :a then
              @a.redo_layout(miny, minx, maxy, minx+@options[:fixed_size])
              @b.redo_layout(miny, minx+@options[:fixed_size]+1, maxy, maxx)
              @border.redo_layout(miny, minx+@options[:fixed_size], maxy, minx+@options[:fixed_size]+1)
            else
              @a.redo_layout(miny, minx, maxy, maxx-@options[:fixed_size]-1)
              @b.redo_layout(miny, maxx-@options[:fixed_size], maxy, maxx)
              @border.redo_layout(miny, maxx-@options[:fixed_size]-1, maxy, maxx-@options[:fixed_size])
            end
          end
        end
      end

      def refresh
        @a.refresh
        @b.refresh
        @border.refresh
      end
    end
    
    class VisualMode
      def initialize(pg_state, debugger_dsl)
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        @state_panel = StatePanel.new(self, pg_state, debugger_dsl)
        @disassembly_panel = DisassemblyPanel.new(self, pg_state, debugger_dsl)
        @minibuffer_panel = MiniBufferPanel.new(self)
      end

      attr_reader :state_panel
      attr_reader :minibuffer_panel
      
      def open
        begin
          Curses.init_screen
          Curses.start_color
          Curses.init_pair(ColorPairs::PC, Curses::COLOR_BLACK, Curses::COLOR_GREEN)
          Curses.init_pair(ColorPairs::Border, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
          Curses.nonl
          Curses.cbreak
          Curses.noecho
          
          @running = true
          @screen = Curses.stdscr
                                                                                  
          root = BSPLayout.new({:dir => :vert, :fixed_item => :b, :fixed_size => 1},
                               BSPLayout.new({:dir => :horiz, :fixed_item => :a, :fixed_size => 28*2},
                                             @state_panel,
                                             @disassembly_panel),
                               @minibuffer_panel)
          root.redo_layout(0, 0, Curses.lines, Curses.cols)
          root.refresh
          
          @active_panel = @disassembly_panel
          
          while @running do
            chr = @active_panel.window.getch
            if chr == Curses::KEY_RESIZE then
              root.redo_layout(0, 0, Curses.lines, Curses.cols)
              next
            end

            if(!@active_panel.handle_key(chr)) then
              case chr
              when "q"
                @running = false
              end
            end
          end
        ensure
          Curses.close_screen
        end
      end
    end
  end
end
