@memInfo||= new Types::MemInfo
@pageInfo||= new Types::PageInfo

def walk_mem_map
  ptr = Pointer.new(@switch, 0)
  
  permissions = ["---", "R--", "-W-", "RW-", "--X", "R-X", "-WX", "RWX"]
  while ptr.value < 0x8000000000 do
    SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
    memInfo = @memInfo.deref
    pageInfo = @pageInfo.arrow(:pageFlags)
    puts "0x" + ptr.value.to_s(16).rjust(16, "0") + " " + permissions[memInfo.memoryPermissions] + " 0x" + memInfo.memoryState.to_s(16).rjust(2, "0") + " 0x" + pageInfo.to_s(16).rjust(2, "0")
    ptr+= memInfo.pageSize
  end
end

def dump_all_mem(path)
  ptr = Pointer.new(@switch, 0)

  permissions = ["---", "R--", "-W-", "RW-", "--X", "R-X", "-WX", "RWX"]

  if !Dir.exist?(path) then
    Dir.mkdir(path)
  end

  progressString = "0%".ljust(6, " ")

  totalBytesDumped = 0
  blocks = []
  
  while ptr.value < 0x8000000000 do
    SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
    memInfo = @memInfo.deref
    ptr = memInfo.base
    len = memInfo.pageSize
    nextptr = ptr + len

    if (memInfo.memoryPermissions & 1) > 0 then
      filename = path + "/dump" + "0x" + ptr.value.to_s(16).rjust(16, "0")
      
      File.open(filename, "wb") do |dump|
        # the switch browser seems to have a really nasty habit of dropping long WebSocket packets
        # I thought splitting them up into 16k chunks in JavaScript would work, but apparently
        # it also drops WebSocket packets if I send a bunch of them in quick succession. Maybe
        # it combines them internally.
        while ptr.value < nextptr.value do
          toRead = [len, 1024 * 16].min
          dump.write(ptr.read(toRead) do |buf, read, total|
                       STDOUT.print "\b" * progressString.length
                       progressString = "0x" + (ptr.value + read).to_s(16).rjust(16, "0") + " " + permissions[memInfo.memoryPermissions].to_s
                       STDOUT.print progressString
                       STDOUT.flush
                     end)
          ptr+= toRead
        end
        
        blocks.push({:memInfo => memInfo, :ptr => ptr, :filename => filename})
        totalBytesDumped+= len
      end
    end
    ptr = nextptr
  end

  STDOUT.print "\b" * progressString.length
  STDOUT.puts "100%"
  puts "Saving flags and radare2 script"
  
  File.open(path + "/flags.csv", "w") do |flags|
    File.open(path + "/load.r2", "w") do |r2|
      blocks.each do |block|
        if block[:memInfo].memoryPermissions & 1 > 0 then
          r2.puts "on #{block[:filename]} 0x#{base.value.to_s(16)}"
        end
      end
      
      ["base_addr", "main_addr", "sp", "tls"].each do |flag|
        r2.puts "f #{flag} @ 0x#{send(flag).to_s(16).rjust(16, "0")}"
        flags.puts "#{flag},0x#{send(flag).to_s(16).rjust(16, "0")}"
      end
    end
  end
end
