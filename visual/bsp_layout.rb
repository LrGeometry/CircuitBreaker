require_relative "border_panel.rb"

module Visual
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
end
