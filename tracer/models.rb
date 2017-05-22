class TracePage < Sequel::Model
  SIZE = 0x2000
  
  def offset
    header.unpack("Q<*")[0]
  end

  def size
    header.unpack("Q<*")[1]
  end

  def apply(pg_state, force=false)
    memory_mapping = pg_state.memory_mapping
    if(memory_mapping[offset/SIZE] != self || force) then
      pg_state.uc.mem_write(offset, data)
      memory_mapping[offset/SIZE] = self
    end
  end
end

# a trace state keeps track of what regions of memory are updated while
# it is active. when the trace state is changed, the current one will "finalize".
# this finalization process involved creating new memory blocks for the databse
# wherever memory was updated while the trace state was active.
# these will be added to "trace_pages".
# the previous blocks will be added to "previous_pages" so that the state can be
# "rewound" and the effects on the machine's state during the period the state was
# active will be undone.

class TraceState < Sequel::Model
  many_to_many :trace_pages
  many_to_many :previous_pages, :class => TracePage, :join_table => :trace_state_previous_pages, :left_key => :trace_state_id, :right_key => :trace_page_id
  many_to_one :parent, :class => self

  def initialize(*args)
    super(*args)
  end

  # rewind state to beginning of parent
  def rewind(pg_state)
    reload(pg_state)
    @dirty_pages||= Array.new
    @dirty_pages.clear
    
    previous_pages.each do |page|
      page.apply(pg_state)
    end
    parent = self.parent
    parent.apply_state(pg_state)
    
    pg_state.trace_state = self.parent
  end

  def apply_state(pg_state)
    fields = state.unpack("Q<*").each
    uc = pg_state.uc
    31.times do |i|
      uc.reg_write(pg_state.x_reg(i), fields.next || 0)
    end
    (Unicorn::UC_ARM64_REG_Q0..Unicorn::UC_ARM64_REG_Q31).each do |reg|
      low = fields.next
      high = fields.next
      uc.reg_write(reg, [low, high])
    end
    uc.reg_write(Unicorn::UC_ARM64_REG_NZCV, fields.next)
    uc.reg_write(Unicorn::UC_ARM64_REG_SP, fields.next)
    pg_state.pc = fields.next
    pg_state.instruction_count = self.instruction_count
  end
  
  def apply(pg_state)
    trace_pages.each do |page|
      page.apply(pg_state)
    end

    apply_state(pg_state)
    @dirty_pages||= Array.new
    @dirty_pages.clear
    
    pg_state.trace_state = self
  end

  # discard all modifications made since this state was saved
  def reload(pg_state)
    if pg_state.trace_state != self then
      raise "cannot reload to different trace state"
    end
    @dirty_pages.each do |page|
      page.apply(pg_state, true)
    end
    @dirty_pages.clear
    apply_state(pg_state)
  end

  def build_state(pg_state)
    x_regs = 31.times.map do |i|
      pg_state.uc.reg_read(pg_state.x_reg(i))
    end.pack("Q<*")
    float_regs = (Unicorn::UC_ARM64_REG_Q0..Unicorn::UC_ARM64_REG_Q31).each.map do |reg|
      pg_state.uc.reg_read(reg).pack("Q<Q<")
    end.join()
    misc_regs = [
      pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_NZCV),
      pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_SP),
      pg_state.pc
    ].pack("Q<*")
    return x_regs + float_regs + misc_regs
  end
    
  def dirty(pg_state, addr, size)
    walk = (addr/TracePage::SIZE).floor*TracePage::SIZE
    while walk < addr + size do
      page = pg_state.memory_mapping[walk/TracePage::SIZE]
      if !@dirty_pages.include? page then
        @dirty_pages.push page
      end
      walk+= TracePage::SIZE
    end
  end

  # saves all modifications into new state
  def create_child(pg_state)
    db.transaction do
      child = TraceState.create(:state => build_state(pg_state), :parent => self, :tree_depth => self.tree_depth+1)
      
      uc = pg_state.uc
      @dirty_pages.each do |p|
        child.add_previous_page(p)
        new_page = TracePage.create(:header => p.header, :data => uc.mem_read(p.offset, p.size))
        child.add_trace_page(new_page)
      end
      
      child.save
      return child
    end
  end

  def parent_at_depth(d)
    if self.tree_depth < d then
      raise "can't get deeper parent"
    end
    walker = self
    while walker.tree_depth > d do
      walker = walker.parent
    end
    return walker
  end
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
    parts = [pos].pack("Q<").unpack("L<L<")
    self.mostsig_pos = parts[1]
    self.leastsig_pos = parts[0]
  end
end
