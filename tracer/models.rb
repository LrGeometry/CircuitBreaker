class TraceState < Sequel::Model
  many_to_many :trace_pages
  many_to_one :parent, :class => self

  def initialize(*args)
    super(*args)
    @dirty = []
  end
  
  def load_state(pg_state)
    uc = pg_state.uc
    memory_mapping = pg_state.memory_mapping
    
    trace_pages.each do |page|
      if(memory_mapping[page.offset] != page) then
        uc.mem_write(page.offset, page.data)
        memory_mapping[page.offset] = page
      end
    end

    fields = state.unpack("Q<*")
    
    for i in 0..28 do
      uc.reg_write(Unicorn::UC_ARM64_REG_X0 + i, fields[i])
    end
    for i in 29..30 do
      uc.reg_write(Unicorn::UC_ARM64_REG_X29 + (i-29), fields[i])
    end

    pg_state.trace_state = self
  end

  def dirty(addr, size)
    @dirty+= [addr, size]
  end
  
  def create_child
    puts "creating child"
    db.transaction do
      child = TraceState.create(:state => state, :parent => self)
      trace_pages.each do |tp|
        child.add_trace_page(tp)
      end
      child.save
      return child
    end
  end
end

class TracePage < Sequel::Model
  SIZE = 0x10000
  
  def offset
    header.unpack("Q<*")[0]
  end

  def size
    header.unpack("Q<*")[1]
  end
  
  many_to_many :trace_states
end

class MappingBlock < Sequel::Model(:memory_mapping_blocks)
  def offset
    header.unpack("Q<*")[0]
  end

  def size
    header.unpack("Q<*")[1]
  end

  def state
    header.unpack("Q<*")[2]
  end

  def perms
    header.unpack("Q<*")[3]
  end

  def pageInfo
    header.unpack("Q<*")[4]
  end  
end

class Flag < Sequel::Model
  def position
    actual_position.unpack("Q<")[0]
  end

  def position=(pos)
    self.actual_position = [pos].pack("Q<")
  end
end
