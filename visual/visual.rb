require_relative "memory_editor.rb"
require_relative "bsp_layout.rb"

module Visual
  module ColorPairs
    IDAllocator = 1.upto(Float::INFINITY)
    PC = IDAllocator.next
    Border = IDAllocator.next
    PostIDAllocator = IDAllocator.next.upto(Float::INFINITY)
  end        
end
