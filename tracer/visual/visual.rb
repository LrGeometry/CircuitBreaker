require_relative "../../visual/visual.rb"
require_relative "disassembly_panel.rb"
require_relative "state_panel.rb"

module Tracer
  module Visual
    include ::Visual
    ColorPairs = ::Visual::ColorPairs
    BSPLayout = ::Visual::BSPLayout
    
    class VisualMode < ::Visual::Mode
      ColorPairs = Visual::ColorPairs
      BSPLayout = Visual::BSPLayout
      
      def initialize(pg_state, debugger_dsl)
        super()
        @pg_state = pg_state
        @debugger_dsl = debugger_dsl
      end

      attr_reader :state_panel
      attr_reader :disassembly_panel
      attr_reader :memedit_panel
      
      def state_change
        @disassembly_panel.refresh
        @memedit_panel.refresh
        @state_panel.refresh
      end
      
      def open
        @memio||= SynchronousMemoryInterface.new(@debugger_dsl)
        @memio.open do
          super do
            @state_panel||= StatePanel.new(self, @pg_state, @debugger_dsl)
            @disassembly_panel||= DisassemblyPanel.new(self, @pg_state, @debugger_dsl)
            
            highlight = Visual::MemoryEditorPanel::Highlight
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

            @active_panel = @disassembly_panel
            
            next BSPLayout.new(
              {:dir => :horiz, :fixed_item => :a, :fixed_size => 28*2},
              @state_panel,
              BSPLayout.new(
                {:dir => :horiz, :fixed_item => :b, :fixed_size => 16*4},
                @disassembly_panel,
                @memedit_panel))
          end
        end
      end
    end
  end
end
