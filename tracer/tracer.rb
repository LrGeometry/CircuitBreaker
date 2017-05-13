require "unicorn"
require "unicorn/arm64_const"
require "crabstone"
require "sequel"
require "pry"

require_relative "dsl.rb"

module Tracer
  RETURN_VECTOR = 0x0000DEADBEEF000000
  HEAP_ADDRESS  = 0x0001DEADBEEF000000
  HEAP_SIZE = 64 * 1024 * 1024 # 64 MiB
  
  class ProgramState
    def initialize(db)
      @memory_mapping = {}
      @uc = Unicorn::Uc.new Unicorn::UC_ARCH_ARM64, Unicorn::UC_MODE_ARM
      @db = db

      @cs = Crabstone::Disassembler.new(Crabstone::ARCH_ARM64, Crabstone::MODE_ARM)
      
      @uc.hook_add(Unicorn::UC_HOOK_MEM_WRITE, Proc.new do |uc, addr, size, user_data|
                     #@trace_state.dirty addr, size
                   end)

      @uc.hook_add(Unicorn::UC_HOOK_CODE, Proc.new do |uc, addr, size, user_data|
                     if(addr == Tracer::RETURN_VECTOR) then
                       @uc.emu_stop
                     end
                     @cs.disasm(uc.mem_read(addr, size), addr).each do |i|
                       puts addr.to_s(16) + ": " + i.mnemonic + " " + i.op_str
                     end
                   end)
      
      @alloc = Allocator.new(self)
    end

    attr_reader :db
    attr_reader :uc
    attr_reader :memory_mapping
    attr_reader :alloc
    attr_accessor :trace_state
  end

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
  
  def self.initialize
    if ARGV.length < 2 || ARGV.length > 3 then
      puts "Usage: repl.rb tracer <memdump/> [<adapter>://tracedb]"
      exit 1
    end

    dump_path = ARGV[1]
    
    if(!Dir.exist?(dump_path)) then
      raise "#{ARGV[0]}: directory not found"
    end

    if(!File.exist?(File.join(dump_path, "blocks.csv"))) then
      raise "#{File.join(dump_path, "blocks.csv")}: file not found"
    end

    if(File.exist?("tracer/quotes.txt")) then # don't let a missing quotes file crash the whole program
      File.open("tracer/quotes.txt", "r") do |quotes|
        puts quotes.each.to_a.sample
      end
    end
    
    tracedb_path = "sqlite://" + File.join(dump_path, "tracedb.sqlite")
    if(ARGV.length > 2) then
      tracedb_path = ARGV[2]
    end
    
    Sequel.extension :migration
    db = Sequel.connect(tracedb_path)
    if(!Sequel::Migrator.is_current?(db, "tracer/migrations")) then
      puts "Migrating database..."
      Sequel::Migrator.run(db, "tracer/migrations")
    end

    Sequel::Model.db = db
    
    require_relative "./models.rb"
    
    if(TraceState.count == 0) then
      STDOUT.print "Creating trace state 0 and mapping blocks... "
      db[:trace_states].insert(:id => 0, :parent_id => 0) # force id = 0
      ts = TraceState[0]
      ts.state = 0.chr * 512
      
      progressString = ""
      
      db.transaction do
        File.open(File.join(dump_path, "blocks.csv"), "r") do |blocks|
          blocks.gets # skip header
          blocks.each do |line|
            parts = line.split(",")
            fname = parts[0]
            offset = parts[1].to_i(16)
            size = parts[2].to_i
            state = parts[3].to_i
            perms = parts[4].to_i
            pageInfo = parts[5].to_i
            
            MappingBlock.create(:header => [offset, size, state, perms, pageInfo].pack("Q<*"))
            
            File.open(File.join(dump_path, "..", fname), "rb") do |block|
              i = 0
              while i < size do
                pageSize = (perms & 2 > 1) ? [size-i, TracePage::SIZE].min : size
                page = TracePage.create(:header => [offset+i, pageSize].pack("Q<*"),
                                        :data => block.read(pageSize))
                i+= pageSize
                ts.add_trace_page(page)
                
                STDOUT.print "\b" * progressString.length
                progressString = ((offset+i).to_s(16)).ljust(progressString.length)
                STDOUT.print progressString
                STDOUT.flush
              end
            end
          end
        end
        
        ts.save
        
        STDOUT.print "\b" * progressString.length
        progressString = ("finalizing...").ljust(progressString.length)
        STDOUT.print progressString
        STDOUT.flush
      end
      STDOUT.print "\b" * progressString.length
      puts "done".ljust(progressString.length)

      if(HEAP_SIZE % TracePage::SIZE != 0) then
        raise "heap size is not a multiple of trace page size"
      end
      
      puts "Creating heap..."
      db.transaction do
        addr = HEAP_ADDRESS
        MappingBlock.create(:header => [addr, HEAP_SIZE, 0xDEADBEEF, 3, 0].pack("Q<*"))
        while(addr < HEAP_ADDRESS + HEAP_SIZE) do
          page = TracePage.create(:header => [addr, TracePage::SIZE].pack("Q<*"),
                                  :data => (0.chr * TracePage::SIZE))
          ts.add_trace_page(page)
          addr+= TracePage::SIZE
        end
        ts.save
      end
      
      puts "Creating flags..."
      File.open(File.join(dump_path, "flags.csv"), "r") do |flags|
        flags.gets # skip hedaer
        flags.each do |line|
          parts = line.split(",")
          flag = Flag.new()
          flag.name = parts[0]
          flag.position = parts[1].to_i(16)
          flag.save
        end
      end
    end

    pg_state = ProgramState.new(db)
    
    puts "Loading memory map..."
    MappingBlock.each do |block|
      pg_state.uc.mem_map(block.offset, block.size, block.perms)
    end
    
    puts "Loading trace state 0..."
    TraceState[0].load_state(pg_state)
    puts "Loaded. Ready to roll."

    $dsl = Tracer::DSL.new(pg_state)
    require_relative "../standard_switch.rb"
    return $dsl
  end
end
