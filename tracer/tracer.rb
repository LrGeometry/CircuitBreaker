require "unicorn"
require "unicorn/arm64_const"
require "crabstone"
require "sequel"
require "pry"
require "fiber"

require_relative "./dsl.rb"
require_relative "./debugger_dsl.rb"
require_relative "./hle/kernel.rb"
require_relative "./allocator.rb"

module Tracer
  RETURN_VECTOR = 0x0000DEADBEEF000000
  HEAP_ADDRESS  = 0x0001DEADBEEF000000
  HEAP_SIZE = 8 * 1024 * 1024 # 8 MiB
  
  class ProgramState
    def initialize(db)
      @memory_mapping = {}
      @instructions_until_break = -1
      @pc = 0
      @uc = Unicorn::Uc.new Unicorn::UC_ARCH_ARM64, Unicorn::UC_MODE_ARM
      @db = db
      @alloc = Tracer::Allocator.new(self)
      @cs = Crabstone::Disassembler.new(Crabstone::ARCH_ARM64, Crabstone::MODE_ARM)
      @temp_flags = []
      @stop_reason = nil
      @kernel_hle = Tracer::HLE::Kernel.new(self)
      
      @uc.hook_add(Unicorn::UC_HOOK_MEM_WRITE, Proc.new do |uc, access, addr, size, value, user_data|
                     @trace_state.dirty(self, addr, size)
                   end)

      @uc.hook_add(Unicorn::UC_HOOK_CODE, Proc.new do |uc, addr, size, user_data|
                     @pc = addr
                     was_first_instruction = @is_first_instruction
                     @is_first_instruction = false
                     if(addr == Tracer::RETURN_VECTOR) then
                       @stop_reason = :reached_return_vector
                       @uc.emu_stop
                       next
                     end
                     if(addr == @break_at && !was_first_instruction) then
                       @stop_reason = :reached_explicit_breakpoint
                       @uc.emu_stop
                       next
                     end
                     if @instructions_until_break == 0 then
                       @stop_reason = :steps_exhausted
                       @uc.emu_stop
                       next
                     else
                       if @instructions_until_break > 0 then
                         @instructions_until_break-= 1
                       end
                     end
                     @instruction_count+= 1
                   end)

      @uc.hook_add(Unicorn::UC_HOOK_INTR, Proc.new do |uc, value, ud|
                     syndrome = @uc.query(Unicorn::UC_QUERY_EXCEPTION_SYNDROME)
                     ec = syndrome >> 26 # exception class
                     iss = syndrome & ((1 << 24)-1)
                     if ec == 0x15 then # SVC instruction execution taken from AArch64
                       begin
                         @kernel_hle.invoke_svc(iss)
                       rescue => e
                         @stop_reason = :svc_error
                         @svc_error = e
                         @instruction_count-= 1 # we already counted this instruction, but don't actually want to count it since we're breaking
                         @uc.emu_stop
                       end
                     else
                       @stop_reason = :unhandled_exception
                       @exception_syndrome = syndrome
                       @instruction_count-= 1
                       @uc.emu_stop
                       next
                     end
                   end)
      
      @uc.mem_map(RETURN_VECTOR, 0x1000, 5)
      @uc.mem_write(RETURN_VECTOR, [0xd503201f].pack("Q<"))
      @uc.reg_write(Unicorn::UC_ARM64_REG_SP, Flag[:name => "sp"].position)
      @uc.reg_write(Unicorn::UC_ARM64_REG_TPIDRRO_EL0, Flag[:name => "tls"].position)
      # enable NEON
      @uc.reg_write(Unicorn::UC_ARM64_REG_CPACR_EL1, 3 << 20)
    end

    def x_reg(num)
      case num
      when 0..28
        return Unicorn::UC_ARM64_REG_X0 + num
      when 29
        return Unicorn::UC_ARM64_REG_X29
      when 30
        return Unicorn::UC_ARM64_REG_X30
      else
        raise "invalid register"
      end
    end
    
    def emu_start(addr, ret)
      @pc = addr
      @uc.reg_write(Unicorn::UC_ARM64_REG_PC, @pc)
      Fiber.new do |cmd|
        while !cmd[:stop] do
          if cmd[:instruction_count] then
            @instructions_until_break = cmd[:instruction_count]
          else
            @instructions_until_break = -1
          end
          @break_at = ret
          if cmd[:break_at] then
            @break_at = cmd[:break_at]
          end
          @stop_reason = nil
          @is_first_instruction = true
          @uc.emu_start(@pc, ret)
          @uc.reg_write(Unicorn::UC_ARM64_REG_PC, @pc)
          
          cmd = Fiber.yield @stop_reason
        end
      end
    end

    def add_temp_flag(flag)
      @temp_flags.push flag
      @temp_flags.sort! do |a, b|
        a.position <=> b.position
      end
    end
    
    def find_flag_by_name(name)
      @temp_flags.find do |f|
        f.name == name
      end || Flag[:name => name.to_s]
    end

    def find_flag_by_before(pos)
      tflag_idx = @temp_flags.rindex do |f|
        f.position <= pos
      end
      tflag = tflag_idx != nil ? @temp_flags[tflag_idx] : nil
      
      addr_parts = [pos].pack("Q<").unpack("L<L<")
      dbflag = flag = Flag.where do
        mostsig_pos <= addr_parts[1]
      end.where do
        leastsig_pos <= addr_parts[0]
      end.order(:mostsig_pos).order_append(:leastsig_pos).last

      if tflag == nil then
        return dbflag
      else
        return [tflag, dbflag].max do |a, b|
          a.position <=> b.position
        end
      end
    end

    def load_state(target)
      current = @trace_state
      current.reload(self) # reset to known clean state
      
      depth = [current.tree_depth, target.tree_depth].min
      current_parent = current.parent_at_depth(depth)
      target_parent = target.parent_at_depth(depth)
      while current_parent != target_parent do
        if current_parent.tree_depth != target_parent.tree_depth then
          raise "tree depth mismatch, is the database ok?"
        end
        if current_parent.tree_depth == 0 then
          raise "no common ancestor"
        end
        current_parent = current_parent.parent
        target_parent = target_parent.parent
      end

      common_parent = current_parent

      rewind_to_state(common_parent)
      forward_to_state(target)
    end

    # preconditions: target is an ancestor of current
    def rewind_to_state(target)
      current = @trace_state
      while current != target do
        current = current.rewind(self)
      end
    end

    # preconditions: current is an ancestor of target
    def forward_to_state(target)
      current = @trace_state
      states = []
      walker = target
      while walker != current do
        states.push(walker)
        walker = walker.parent
      end
      states.reverse!
      states.each do |state|
        state.apply(self)
      end
    end
    
    attr_reader :db
    attr_reader :uc
    attr_reader :cs
    attr_reader :memory_mapping
    attr_reader :alloc
    attr_reader :temp_flags
    attr_accessor :pc
    attr_accessor :trace_state
    attr_accessor :debugger_dsl
    attr_accessor :instruction_count
  end

  TempFlag = Struct.new("TempFlag", :name, :position)
  
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
      $db = db
      Sequel::Migrator.run(db, "tracer/migrations")
    end

    Sequel::Model.db = db
    
    require_relative "./models.rb"
    
    if(TraceState.count == 0) then
      STDOUT.print "Creating trace state 0 and mapping blocks... "
      db[:trace_states].insert(:id => 0, :parent_id => 0) # force id = 0
      ts = TraceState[0]
      ts.state = 0.chr * ((31 + (32*2) + 3) * 8)
      ts.tree_depth = 0
      ts.instruction_count = 0
      
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
                pageSize = (perms & 2 > 0) ? [size-i, TracePage::SIZE].min : size-i
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
    TraceState[0].apply(pg_state)
    puts "Loaded. Ready to roll."
    
    $dsl = Tracer::DSL.new(pg_state)
    require_relative "../standard_switch.rb"
    return $dsl
  end
end
