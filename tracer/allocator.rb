module Tracer
  class Allocator
    def initialize(pg_state)
      @chain = MemoryBlock.new(HEAP_ADDRESS, HEAP_SIZE, nil, nil, nil, nil)
      @chain.before = @chain
      @chain.after = @chain
      @chain.before_free = @chain
      @chain.after_free = @chain
      @blockMap = {}
    end

    attr_accessor :chain

    def malloc(size)
      block = @chain.allocate(self, @chain, size)
      @blockMap[block.address] = block
      return block.address
    end

    def free(addr)
      if !@blockMap[addr] then
        raise "this address is not the start of a block"
      end
      @blockMap[addr].free(self)
      @blockMap.delete addr
    end
    
    class MemoryBlock
      def initialize(address, size, before, after, before_free, after_free)
        @address = address
        @size = size
        @before = before
        @after = after
        @before_free = before_free
        @after_free = after_free
        @allocated = false
      end

      attr_accessor :allocated
      attr_accessor :before
      attr_accessor :after
      attr_accessor :before_free
      attr_accessor :after_free
      attr_accessor :address
      attr_accessor :size

      def inspect
        "0x" + @address.to_s(16).rjust(16, "0") + ", 0x" + @size.to_s(16) + " bytes long"
      end
      
      def coalesce_before(allocator)
        if @allocated || @before.allocated then
          raise "cannot coalesce allocated blocks"
        end
        if @address < @before.address then
          raise "cannot coalesce across circular heap boundary"
        end
        @address = @before.address
        @size+= @before.size
        @before.before.after = self
        @before.before_free.after_free = self
        @before.after_free.before_free = self
        @after_free = @before.after_free
        if allocator.chain == @before then
          allocator.chain = self
        end
        @before = @before.before
      end

      def free(allocator)
        @allocated = false
        # insert ourselves into the free list
        walker = @after
        while walker.allocated do
          walker = walker.after
        end
        @after_free = walker
        @after_free.before_free = self
        walker = @before
        while walker.allocated do
          walker = walker.before
        end
        @before_free = walker
        @before_free.after_free = self

        if !@before.allocated && @address > @before.address then
          coalesce_before(allocator)
        end
        if !@after.allocated && @address < @after.address then
          @after.coalesce_before(allocator)
        end
      end

      def remove_from_chain(allocator)
        if allocator.chain == self then
          allocator.chain = @after
        end
        @before.after = @after
        @after.before = @before
        if @before_free.after_free == self then
          @before_free.after_free = @after_free
        else
          raise "?"
        end
        if @after_free.before_free == self then
          @after_free.before_free = @before_free
        else
          raise "?"
        end
      end
      
      def allocate(allocator, start, size) # 'start' is to prevent cycles
        allocator.chain = self

        if @before_free.allocated then
          raise "@before_free has been allocated, something is horribly wrong"
        end

        if @after_free.allocated then
          raise "@after_free has been allocated, something is horribly wrong"
        end

        if @allocated then
          raise "I have been allocated, something is horribly wrong"
        end
        
        if @size >= size then
          # @before_free and @after_free are nilled out so we don't accidentally use them since
          # we aren't in the free list anymore
          new_block = MemoryBlock.new(@address, size, @before, self, nil, nil)
          new_block.allocated = true
          @address+= size
          @size-= size
          @before.after = new_block
          @before.after_free = self # not really necessary but helpful to understand
          @before = new_block
          @before_free.after_free = self
          if @size == 0 then
            remove_from_chain
          end
          return new_block
        else
          if @after_free != start then
            @after_free.allocate(size)
          else
            raise "out of memory"
          end
        end
      end
    end
  end
end
