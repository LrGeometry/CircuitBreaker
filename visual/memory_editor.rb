module Visual
  class MemoryEditorPanel
    def initialize(initial_cursor, highlighters, memio)
      @window = Curses::Window.new(0, 0, 0, 0)
      @highlighters = highlighters
      @memio = memio
      @cursor = initial_cursor
      @color_mgr = HighlightColorManager.new
      @color_mgr.add_color(:fg, Curses::COLOR_WHITE)
      @color_mgr.add_color(:bg, Curses::COLOR_BLACK)
      @color_mgr.add_color(:pc, Curses::COLOR_GREEN)
      @color_mgr.add_color(:reg, Curses::COLOR_BLUE)
      @color_mgr.add_color(:cursor, Curses::COLOR_RED)
    end

    attr_accessor :cursor
    
    Highlight = Struct.new("Highlight", :name, :value, :color)

    class HighlightColorManager
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

      registers = @highlighters.map do |h|
        h.call
      end.flatten(1)
      
      start = @center - (@height/2) * 16 # 16 bytes per line
      (@height-1).times do |i|
        line_start = start + i * 16
        line_end = start + (i+1) * 16

        @window.attroff(Curses::A_UNDERLINE)
        @window.setpos(i+1, 0)

        content = @memio.read_sync(line_start, 16)
        
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
end

class SynchronousMemoryInterface
  def initialize(dsl)
    @dsl = dsl
  end

  def read(addr, size)
    yield @dsl.read(addr, 0, size)
  end

  def read_sync(addr, size)
    read(addr, size) do |val|
      return val
    end
  end
  
  def write(addr, value)
    @dsl.write(addr, 0, value)
    yield
  end

  def permissions(addr)
    yield @dsl.memory_permissions(addr)
  end

  def open
    yield self
  end
end

require "thread"

class AsynchronousMemoryInterface
  def initialize(dsl)
    @dsl = dsl
    @io_queue = Queue.new
  end

  def read(addr, size, &block)
    @io_queue.push({:type => :read, :addr => addr.to_i, :size => size.to_i, :block => block})
  end

  def write(addr, data, &block)
    @io_queue.push({:type => :write, :addr => addr.to_i, :data => data, :block => block})
  end

  def permissions(addr, &block)
    @io_queue.push({:type => :permissions, :addr => addr.to_i, :block => block})
  end
  
  def open
    thread = Thread.new do
      begin
        yield self
        @io_queue.push({:type => :exit})
      rescue => e
        @io_queue.push({:type => :exit, :error => e})
      end
    end
    
    job = @io_queue.pop
    while job[:type] != :exit do
      case job[:type]
      when :read
        job[:block].call(@dsl.read(job[:addr], 0, job[:size]))
      when :write
        @dsl.write(job[:addr], 0, job[:data])
        job[:block].call()
      when :permissions
        job[:block].call(@dsl.memory_permissions(@dsl.make_pointer(job[:addr])))
      end
      job = @io_queue.pop
    end

    if job[:error] then # propogate exceptions
      raise job[:error]
    end
  end
end
