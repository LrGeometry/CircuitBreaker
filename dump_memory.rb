@memInfo||= new Types::MemInfo
@pageInfo||= new Types::PageInfo

def dump_all_mem(path)
  ptr = Pointer.new(@switch, 0)

  permissions = ["---", "R--", "-W-", "RW-", "--X", "R-X", "-WX", "RWX"]

  if !Dir.exist?(path) then
    Dir.mkdir(path)
  end

  STDOUT.print "Walking memory list... "
  STDOUT.flush
  progressString = ""
  blocks = []
  totalDumpSize = 0
    
  File.open(path + "/mem_mapping.csv", "w") do |mem|
    mem.puts "base,size,state,permissions,pageFlags"
    while ptr.value < 0x8000000000 do
      STDOUT.print "\b" * progressString.length
      progressString = "0x" + ptr.value.to_s(16).rjust(16, "0")
      STDOUT.print progressString
      STDOUT.flush
      SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
      memInfo = @memInfo.deref
      pageInfo = @pageInfo.deref
      blocks.push({:ptr => ptr, :memInfo => memInfo, :pageInfo => pageInfo})
      if (memInfo.memoryPermissions & 1) > 0 then
        totalDumpSize+= memInfo.pageSize
      end
      mem.puts "#{ptr.value},#{memInfo.pageSize},#{memInfo.memoryState},#{memInfo.memoryPermissions},#{pageInfo.pageFlags}"
      ptr+= memInfo.pageSize
    end
  end

  puts

  puts "Finished walking memory list"
  
  progressString = "0%".ljust(6, " ")

  totalBytesDumped = 0
    
  blocks.each do |block|
    if block[:memInfo].memoryPermissions & 1 > 0 then
      filename = path + "/dump" + "0x" + ptr.value.to_s(16).rjust(16, "0")
      
      File.open(filename, "wb") do |dump|
        ptr = block[:memInfo].base
        nextptr = ptr + block[:memInfo].pageSize
        
#        while ptr.value < nextptr.value do
          #len = [nextptr-ptr, 1024*256].min
          len = nextptr-ptr
          
          dump.write(ptr.read(len) do |buf, read, total|
                       STDOUT.print "\b" * progressString.length
                       progressString = (((totalBytesDumped + read)*100.0/totalDumpSize).round(2).to_s + "%").ljust(6, " ") + " 0x" + ptr.value.to_s(16).rjust(16, "0") + " " + permissions[block[:memInfo].memoryPermissions].to_s
                       STDOUT.print progressString
                       STDOUT.flush
                     end)
         
          #dump.write(ptr.read(len))
          ptr+= len
          totalBytesDumped+= len
#        end
      end
    end
  end

  STDOUT.print "\b" * progressString.length
  STDOUT.puts "100%".ljust(6, " ")
  puts "Saving flags and radare2 script"
  
  File.open(path + "/flags.csv", "w") do |flags|
    File.open(path + "/load.r2", "w") do |r2|
      blocks.each do |block|
        if block[:memInfo].memoryPermissions & 1 > 0 then
          r2.puts "on #{filename} 0x#{base.value.to_s(16)}"
        end
      end
      
      ["base_addr", "main_addr", "sp", "tls"].each do |flag|
        r2.puts "f #{flag} @ 0x#{send(flag).to_s(16).rjust(16, "0")}"
        flags.puts "#{flag},0x#{send(flag).to_s(16).rjust(16, "0")}"
      end
    end
  end
end
