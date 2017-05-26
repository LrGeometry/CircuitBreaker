module Tracer
  module Visual
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
  end
end
