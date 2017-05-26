require "curses"
require "rainbow"

module Tracer
  module Visual
    module ColorPairs
      IDAllocator = 1.upto(Float::INFINITY)
      PC = IDAllocator.next
      Border = IDAllocator.next
      PostIDAllocator = IDAllocator.next.upto(Float::INFINITY)
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

    class MemoryViewerPanel
      def initialize(visual, pg_state, debugger_dsl)
        @visual = visual
        @window = Curses::Window.new(0, 0, 0, 0)
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        @cursor = pg_state.pc
        @color_mgr = RegHighlightColorManager.new
        @color_mgr.add_color(:fg, Curses::COLOR_WHITE)
        @color_mgr.add_color(:bg, Curses::COLOR_BLACK)
        @color_mgr.add_color(:pc, Curses::COLOR_GREEN)
        @color_mgr.add_color(:reg, Curses::COLOR_BLUE)
        @color_mgr.add_color(:cursor, Curses::COLOR_RED)
      end

      Register = Struct.new("Register", :name, :value, :color)

      class RegHighlightColorManager
        def initialize
          @colors = []
          @color_map = {}
          @color_pairs = []
        end
        
        def add_color(name, color)
          if name == nil then raise "name is nil" end
          if color == nil then raise "color is nil" end
          id = @colors.size
          @color_map[name] = id
          @color_pairs.each_with_index do |map, i|
            pair_id = ColorPairs::PostIDAllocator.next
            fg = @colors[i]
            Curses.init_pair(pair_id, fg, color)
            map[id] = [pair_id, fg, color]
          end
          @colors[id] = color
          @color_pairs[id] = @colors.map do |bg|
            pair_id = ColorPairs::PostIDAllocator.next
            Curses.init_pair(pair_id, color, bg)
            next [pair_id, color, bg]
          end
        end
        
        def get_pair(fg, bg)
          @color_pairs[@color_map[fg]][@color_map[bg]][0]
        end
      end
      
      def redo_layout(miny, minx, maxy, maxx)
        @window.resize(maxy-miny, maxx-minx)
        @window.move(miny, minx)
        @width = maxx-minx
        @height = maxy-miny
        self.recenter
      end

      def recenter
        @center = @cursor
      end
      
      def refresh
        @window.clear
        @window.setpos(0, 0)
        @window.attron(Curses::color_pair(ColorPairs::Border))
        @window.addstr("Memory Viewer".ljust(@width))
        @window.attroff(Curses::color_pair(ColorPairs::Border))

        registers = []
        registers.push(Register.new("CUR", @visual.disassembly_panel.cursor, :cursor))
        registers.push(Register.new("PC", @pg_state.pc, :pc))
        registers.push(Register.new("SP", @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_SP), :reg))
        31.times do |i|
          registers.push(Register.new("x" + i.to_s, @debugger_dsl.x[i], :reg))
        end
        
        start = @center - (@height/2) * 16 # 16 bytes per line
        (@height-1).times do |i|
          line_start = start + i * 16
          line_end = start + (i+1) * 16

          @window.attroff(Curses::A_UNDERLINE)
          @window.setpos(i+1, 0)

          content = @pg_state.uc.mem_read(line_start, 16)
          
          content.bytes.each_with_index do |b, j|
            addr = line_start + j
            space_width = j == 8 ? 2 : 1
            next_space_width = j == 7 ? 2 : 1

            reg_next_line = registers.find do |r|
              r.value <= (addr+16) && r.value >= (line_start+16)
            end

            reg_at_space = registers.find do |r|
              r.value/4 == addr/4 && r.value != addr
            end
            
            if reg_next_line then
              space_bg = reg_at_space ? reg_at_space.color : :bg
              next_underline_fg = reg_next_line.color
              
              color = @color_mgr.get_pair(next_underline_fg, space_bg)
              
              @window.attron(Curses::color_pair(color))
              @window.attron(Curses::A_BOLD)
              @window.addstr(" " * space_width) # for some reason, the unicode underscores inherit the foreground color but not the background color?
              @window.attroff(Curses::A_BOLD)
              @window.attroff(Curses::color_pair(color))
              @window.addstr("\u0332" * (2+next_space_width)) # unicode combining underscore
            else
              color = @color_mgr.get_pair(reg_at_space ? :bg : :fg, reg_at_space ? reg_at_space.color : :bg)
              @window.attron(Curses::color_pair(color))
              @window.addstr(" " * space_width)
              @window.attroff(Curses::color_pair(color))
            end

            reg = registers.find do |r|
              r.value/4 == addr/4
            end

            color = @color_mgr.get_pair(reg ? :bg : :fg, reg ? reg.color : :bg)
            @window.attron(Curses::color_pair(color))
            @window.addstr(b.to_s(16).rjust(2, "0"))
            @window.attroff(Curses::color_pair(color))
          end

          regs_next_line = registers.select do |r|
            r.value >= (line_start+16) && r.value < (line_end+16)
          end

          regs_next_line_sort = regs_next_line.sort_by do |r| r.value end

          regs_next_line_sort.each_with_index do |r, i|
            reg_effecting_color = regs_next_line.find do |r2|
              regs_next_line_sort.find_index(r2) >= i
            end
            
            color = @color_mgr.get_pair(reg_effecting_color.color, :bg)
            @window.attron(Curses::A_BOLD)
            @window.attron(Curses::color_pair(color))
            @window.addstr(i == 0 ? " " : (regs_next_line_sort[i-1].value == r.value ? "\u0332&" : "\u005f")) # receives underline from previous iteration
            @window.attroff(Curses::color_pair(color))

            color = @color_mgr.get_pair(r.color, :bg)
            @window.attron(Curses::color_pair(color))
            @window.addstr("\u0332" * (r.name.length) + r.name) # unicode combining underscore
            @window.attroff(Curses::color_pair(color))
            @window.attroff(Curses::A_BOLD)
          end
        end

        @window.setpos((@cursor - start)/16 + 1, (@cursor%16)*3)
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
        ColorPairs::PostIDAllocator.rewind
      end

      attr_reader :state_panel
      attr_reader :disassembly_panel
      attr_reader :minibuffer_panel
      attr_reader :memviewer_panel

      def state_change
        @disassembly_panel.refresh
        @memviewer_panel.refresh
        @state_panel.refresh
      end
      
      def open
        begin
          Curses.init_screen
          Curses.start_color
          Curses.init_pair(ColorPairs::PC, Curses::COLOR_BLACK, Curses::COLOR_GREEN)
          Curses.init_pair(ColorPairs::Border, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
          Curses.init_pair(67, Curses::COLOR_WHITE, Curses::COLOR_BLACK)

          @state_panel||= StatePanel.new(self, @pg_state, @debugger_dsl)
          @disassembly_panel||= DisassemblyPanel.new(self, @pg_state, @debugger_dsl)
          @memviewer_panel||= MemoryViewerPanel.new(self, @pg_state, @debugger_dsl)
          @minibuffer_panel||= MiniBufferPanel.new(self)
          
          Curses.nonl
          Curses.cbreak
          Curses.noecho
          
          @running = true
          @screen = Curses.stdscr
                                                                                  
          root = BSPLayout.new(
            {:dir => :vert, :fixed_item => :b, :fixed_size => 1},
            BSPLayout.new(
              {:dir => :horiz, :fixed_item => :a, :fixed_size => 28*2},
              @state_panel,
              BSPLayout.new(
                {:dir => :horiz, :fixed_item => :b, :fixed_size => 16*4},
                @disassembly_panel,
                @memviewer_panel)),
            @minibuffer_panel)
          root.redo_layout(0, 0, Curses.lines, Curses.cols)
          root.refresh
          
          @active_panel = @disassembly_panel
          
          while @running do
            @active_panel.window.refresh
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
