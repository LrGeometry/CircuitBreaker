@memInfo||= new Types::MemInfo
@pageInfo||= new Types::PageInfo

def dump_until_none(ptr)
  base = ptr
  SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
  STDOUT.print ptr.inspect
  if @memInfo.arrow(:memoryPermissions) > 0 then
    size = @memInfo.arrow(:pageSize)
    nextptr = ptr + size

    progressString = " 0%"
    STDOUT.print progressString
    
    buf = String.new
    while buf.length < size
      len = [nextptr-ptr, 1024*1024].min
      buf+= ptr.read(len)
      ptr+= len

      STDOUT.print "\b" * progressString.length
      progressString = " " + ((ptr-base)*100.0/size).round(2).to_s + "%"
      STDOUT.print progressString
      STDOUT.flush
    end

    puts
    
    return buf + dump_until_none(nextptr)
  else
    String.new
  end
end
