@memInfo = new Types::MemInfo
@pageInfo = new Types::PageInfo

def walk(ptr)
  SVC::QueryMemory.call(@memInfo, @pageInfo, ptr)
  nextptr = ptr + @memInfo.arrow(:pageSize)

  memPerms = [
    "NONE", "R", "W", "RW", "X", "RX", "WX", "RWX"
  ]
  
  puts "0x" + ptr.value.to_s(16).rjust(16, "0") + " - " + nextptr.value.to_s(16).rjust(16, "0") + " " + memPerms[@memInfo.arrow(:memoryPermissions)]
  walk nextptr
end
