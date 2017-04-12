@memInfo||= new Types::MemInfo
@pageInfo||= new Types::PageInfo

def dump_mem_for_radare2(path)
  ptr = Pointer.new(@switch, 0)
  base = ptr
  SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)

  permissions = ["---", "R--", "-W-", "RW-", "--X", "R-X", "-WX", "RWX"]

  if !Dir.exist?(path) then
    Dir.mkdir(path)
  end
  
  File.open(path + "/commands.r2", "w") do |commands|
    while ptr.value < 0x8000000000 do
      size = @memInfo.arrow(:pageSize)
      nextptr = ptr + size

      STDOUT.print "0x" + ptr.value.to_s(16).rjust(16, "0") + " [" + permissions[@memInfo.arrow(:memoryPermissions)] + "]: "
      
      if @memInfo.arrow(:memoryPermissions) & 1 > 0 then
        progressString = " 0%"
        STDOUT.print progressString
        
        filename = path + "/dump" + "0x" + ptr.value.to_s(16).rjust(16, "0")
        
        File.open(filename, "wb") do |dump|
          while ptr.value < nextptr.value do
            len = [nextptr-ptr, 1024*1024].min
            dump.write(ptr.read(len))
            ptr+= len
            
            STDOUT.print "\b" * progressString.length
            progressString = " " + ((ptr-base)*100.0/size).round(2).to_s + "%"
            STDOUT.print progressString
            STDOUT.flush
          end
        end
        
        puts
      else
        STDOUT.puts "skip"
      end
      
      commands.puts "on #{filename} 0x#{base.value.to_s(16)}"
      
      base = nextptr
      ptr = nextptr
      SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
    end
  end
end
