module Visual
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
end
