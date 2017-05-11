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
  if !Dir.exist?(path) then
    Dir.mkdir(path)
  end

  progressString = ""

  permissions = ["NONE", "R", "W", "RW", "X", "RX", "WX", "RWX"]
  
  pageFile = nil
  filename = nil
  ptr = nil
  currentHeader = nil
  blocks = []
  @switch.command("dumpAllMemory", {}) do |header, data|
    if(header["type"] == "newPage") then
      if(pageFile) then
        pageFile.close
      end
      currentHeader = header
      ptr = Pointer.from_switch(@switch, header["begin"])
      filename = path + "/dump" + "0x" + ptr.value.to_s(16).rjust(16, "0")
      pageFile = File.open(filename, "wb")
      header["filename"] = filename
      blocks.push header
    elsif header["type"] == "pageData" then
      pageFile.write(data)
      ptr+= data.length
    else
      raise "invalid header type"
    end
    
    STDOUT.print "\b" * progressString.length
    progressString = "0x" + ptr.value.to_s(16).rjust(16, "0") + " " + permissions[currentHeader["memPerms"]].to_s
    STDOUT.print progressString
    STDOUT.flush
  end

  puts
    
  puts "Saving flags and radare2 script"
  
  File.open(path + "/load.r2", "w") do |r2|
    File.open(path + "/blocks.csv", "w") do |blocksCsv|
      blocksCsv.puts "filename,begin,size,state,perms,pageInfo"
      blocks.each do |block|
        r2.puts "on #{block["filename"]} 0x#{Pointer.from_switch(@switch, block["begin"]).value.to_s(16)}"
        blocksCsv.puts "#{block["filename"]},0x#{Pointer.from_switch(@switch, block["begin"]).value.to_s(16).rjust(16, "0")},#{block["size"]},#{block["memState"]},#{block["memPerms"]},#{block["pageInfo"]}"
      end
    end

    File.open(path + "/flags.csv", "w") do |flags|
      flags.puts "name,position"
      ["base_addr", "main_addr", "sp", "tls"].each do |flag|
        r2.puts "f #{flag} @ 0x#{send(flag).value.to_s(16).rjust(16, "0")}"
        flags.puts "#{flag},0x#{send(flag).value.to_s(16).rjust(16, "0")}"
      end
    end
  end
end
