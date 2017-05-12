class ROP2_0_0 # ROP-based binprog compiler for Switch OS v2.0.0
  def initialize
    @first = nil
    @last = nil
  end

  class SimpleStackGadget
    def initialize(mref, stack, chain_offset)
      @mref = mref
      @stack = stack.pack("Q<*")
      @chain_offset = chain_offset
    end

    attr_reader :mref
    attr_reader :stack
    
    def chain(next_gadget)
      @stack[@chain_offset, 8] = [next_gadget.mref].pack("Q<") # patch address in
      @next_gadget = next_gadget
    end

    attr_reader :next_gadget
  end

  def chain(gadget)
    if @first == nil then
      @first = gadget
    else
      @first.chain gadget
    end
    @last = gadget
  end
  
  def load_x20_x19(x20, x19)
    # 0x7a9c787b90  ldp x29, x30, [sp, 0x10]
    # 0x7a9c787b94  ldp x20, x19, [sp], 0x20 
    # 0x7a9c787b98  ret
    x29 = 0 # frame pointer
    x30 = 0 # link register, field gets overwritten when chaining
    chain SimpleStackGadget.new(0x581B90, [x20, x19, x29, x30], 0x18)
  end

  def load_and_str_x8(post_x20, post_x19)
    # 0x7a9c67aa98  ldr x8, [x19]            
    # 0x7a9c67aa9c  str x8, [x20]            
    # 0x7a9c67aaa0  ldp x29, x30, [sp, 0x10]
    # 0x7a9c67aaa4  ldp x20, x19, [sp], 0x20 
    # 0x7a9c67aaa8  ret

    x29 = 0 # frame pointer
    x30 = 0 # link register, field gets overwritten when chaining
    chain SimpleStackGadget.new(0x474A98, [post_x20, post_x19, x29, x30], 0x18)
  end

  class SimpleGadget
    def initialize(mref)
      @mref = mref
    end

    attr_reader :mref

    def stack
      String.new
    end

    def chain(next_gadget)
      # must be done manually
    end
  end

  # It is up to you to make sure that [x0+0x100] contains the address of the next gadget.
  # I can't chain this one for you.
  def load_all_registers
    #  0x7a9c639620  ldp x2, x3, [x0, 0x10]   
    #  0x7a9c639624  ldp x4, x5, [x0, 0x20]   
    #  0x7a9c639628  ldp x6, x7, [x0, 0x30]   
    #  0x7a9c63962c  ldp x8, x9, [x0, 0x40]   
    #  0x7a9c639630  ldp x10, x11, [x0, 0x50] 
    #  0x7a9c639634  ldp x12, x13, [x0, 0x60] 
    #  0x7a9c639638  ldp x14, x15, [x0, 0x70] 
    #  0x7a9c63963c  ldp x16, x17, [x0, 0x80] 
    #  0x7a9c639640  ldp x18, x19, [x0, 0x90] 
    #  0x7a9c639644  ldp x20, x21, [x0, 0xa0] 
    #  0x7a9c639648  ldp x22, x23, [x0, 0xb0] 
    #  0x7a9c63964c  ldp x24, x25, [x0, 0xc0] 
    #  0x7a9c639650  ldp x26, x27, [x0, 0xd0] 
    #  0x7a9c639654  ldp x28, x29, [x0, 0xe0] 
    #  0x7a9c639658  ldr x30, [x0, 0x100]
    #  0x7a9c63965c  ldr x1, [x0, 0xf8]
    #  0x7a9c639660  mov sp, x1
    #  0x7a9c639664  ldp d0, d1, [x0, 0x110]  
    #  0x7a9c639668  ldp d2, d3, [x0, 0x120]  
    #  0x7a9c63966c  ldp d4, d5, [x0, 0x130]  
    #  0x7a9c639670  ldp d6, d7, [x0, 0x140]  
    #  0x7a9c639674  ldp d8, d9, [x0, 0x150]  
    #  0x7a9c639678  ldp d10, d11, [x0, 0x160]
    #  0x7a9c63967c  ldp d12, d13, [x0, 0x170]
    #  0x7a9c639680  ldp d14, d15, [x0, 0x180]
    #  0x7a9c639684  ldp d16, d17, [x0, 0x190]
    #  0x7a9c639688  ldp d18, d19, [x0, 0x1a0]
    #  0x7a9c63968c  ldp d20, d21, [x0, 0x1b0]
    #  0x7a9c639690  ldp d22, d23, [x0, 0x1c0]
    #  0x7a9c639694  ldp d24, d25, [x0, 0x1d0]
    #  0x7a9c639698  ldp d26, d27, [x0, 0x1e0]
    #  0x7a9c63969c  ldp d28, d29, [x0, 0x1f0]
    #  0x7a9c6396a0  ldr d30, [x0, 0x200]
    #  0x7a9c6396a4  ldr d31, [x0, 0x208]
    #  0x7a9c6396a8  ldp x0, x1, [x0]         
    #  0x7a9c6396ac  ret
    chain SimpleGadget.new
  end

  def load_all_registers_stage_2
    chain SimpleGadget.new
  end
  
  def compile(program, switch)
    register_state_buffer = switch.malloc(0x400)
    program.operations.each do |op|
      case op.type
      when :call
        # need gadgetry to load values of LR and SP from the stack into the register load area
        0..op.arg_fields.length.times do |i|
          dest_location = register_state_buffer.value + (i * 0x08)
          if i == 0 then
            load_x20_x19(dest_location, program.buffer.value + op.arg_fields[i].location)
          else
            # the name and parameters here are a little confusing.
            # this loads and stores x8 based off of the values of x20 and x19 that were set earlier
            # *then* loads x20 and x19 based off of the parameters.
            load_and_str_x8(dest_location, program.buffer.value + op.arg_fields[i].location)
          end
        end
        load_and_str_x8(0, 0) # copy the last value
        
      else
        raise "unsupported operation '#{op.type}'"
      end
    end
  end
end
