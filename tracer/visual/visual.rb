require "curses"

require_relative "disassembly_panel.rb"
require_relative "minibuffer_panel.rb"
require_relative "state_panel.rb"
require_relative "../../visual/visual.rb"

module Tracer
  module Visual
    include ::Visual
    ColorPairs = ::Visual::ColorPairs
    BSPLayout = ::Visual::BSPLayout
    
    class VisualMode
      ColorPairs = Visual::ColorPairs
      BSPLayout = Visual::BSPLayout
      
      def initialize(pg_state, debugger_dsl)
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
        ColorPairs::PostIDAllocator.rewind
      end

      attr_reader :state_panel
      attr_reader :disassembly_panel
      attr_reader :minibuffer_panel
      attr_reader :memedit_panel
      attr_accessor :active_panel
      
      def state_change
        @disassembly_panel.refresh
        @memedit_panel.refresh
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

          highlight = Visual::MemoryEditorPanel::Highlight
          @memio||= SynchronousMemoryInterface.new(@debugger_dsl)
          @memedit_panel||= ::Visual::MemoryEditorPanel.new(
            @pg_state.pc,
            [Proc.new do
               [highlight.new("CUR", @disassembly_panel.cursor, :cursor)]
             end, Proc.new do
               registers = []
               registers.push(highlight.new("PC", @pg_state.pc, :pc))
               registers.push(highlight.new("SP", @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_SP), :reg))
               31.times do |i|
                 registers.push(highlight.new("x" + i.to_s, @debugger_dsl.x[i], :reg))
               end

               registers
             end
            ], @memio)
          
          @minibuffer_panel||= MiniBufferPanel.new(self)

          @memio.open do
            Curses.nonl
            #Curses.cbreak
            Curses.raw
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
                  @memedit_panel)),
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
                when "q", 3
                  @running = false
                when 26 # ^Z
                  Process.kill("TSTP", Process.pid)
                end
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
