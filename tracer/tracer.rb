require "unicorn"
require "unicorn/arm64_const"
require "sequel"
require "pry"

require_relative "dsl.rb"

module Tracer
  Types = ::Types
  class ProgramState
    def initialize(db)
      @memory_mapping = {}
      @uc = Unicorn::Uc.new Unicorn::UC_ARCH_ARM64, Unicorn::UC_MODE_ARM
      @db = db
      
      @uc.hook_add(Unicorn::UC_HOOK_MEM_WRITE, Proc.new do |uc, addr, size, user_data|
                     @trace_state.dirty addr, size
                   end)

      @uc.hook_add(Unicorn::UC_HOOK_CODE, Proc.new do |uc, addr, size, user_data|
                     puts addr.to_s(16)
                   end)
    end

    attr_reader :db
    attr_reader :uc
    attr_reader :memory_mapping
    attr_accessor :trace_state
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

    dsl = Tracer::DSL.new(pg_state)
    dsl.bind = dsl.instance_exec do
      binding
    end
    dsl.bind.pry
  end
end
