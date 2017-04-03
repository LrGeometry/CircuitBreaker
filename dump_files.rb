@handleBuf = malloc(Types::Handle.size).cast(Types::Handle)
@openDirectory = openDirectory
@readDirectory = readDirectory

@fopen = fopen
@fseek = fseek
@ftell = ftell
@fread = fread
@fclose = fclose

@modeBuf = string_buf "rb"

@dumpSize = 0x20000
@dumpBuf = malloc @dumpSize

def dumpFile(path, target)
  STDOUT.print path

  if File.exists?(target) then
    STDOUT.puts
    return
  end
  
  File.open(target, "wb") do |out|
    pathBuf = string_buf path
    file = @fopen.call(pathBuf, @modeBuf)

    if file.is_null_ptr? then
      STDOUT.puts
      puts "could not open " + path
      return
    end
    
    @fseek.call(file, 0, 2)
    size = @ftell.call(file)
    @fseek.call(file, 0, 0)

    progressString = ""
    
    remaining = size
    while remaining > 0 do
      ret = @fread.call(@dumpBuf, 1, [@dumpSize, remaining].min, file)
      if ret == 0 then
        break
      end
      if ret < 0 then
        puts "read error"
        break
      end
      out.write(@dumpBuf.read(ret))
      STDOUT.print "\b" * progressString.length
      progressString = " " + ((size-remaining)*100.0/size).round(2).to_s + "%"
      STDOUT.print progressString
      STDOUT.flush
      remaining-= ret
    end

    STDOUT.print "\b" * progressString.length
    progressString = " " + ((size-remaining)*100.0/size).round(2).to_s + "%"
    STDOUT.print progressString
    STDOUT.flush
    
    STDOUT.puts
    
    @fclose.call(file)
  end
end

def dump(path, target)
  puts path

  if !Dir.exists?(target) then
    Dir.mkdir(target)
  end
  
  pathBuf = string_buf path
  ret = @openDirectory.call(@handleBuf, pathBuf, 3)
  if ret != 0 then
    raise "could not open directory '#{path}'! got ret " + ret.to_s
  end

  entrySize = 0x310
  numFilesToList = 128
  fileListSize = numFilesToList * entrySize
  sDirInfo = malloc(0x200)
  sFileList = malloc(fileListSize)
  handle = @handleBuf[0]

  ret = @readDirectory.call(sDirInfo, sFileList, handle, numFilesToList)

  fileList = sFileList.read(fileListSize)
  
  numFilesToList.times do |i|
    #    entry = (sFileList + (entrySize * i)).read(entrySize).unpack("Z772L<L<")
    entry = fileList[i * entrySize, (i+1) * entrySize]#.unpack("Z772L<L<")
    name = String.new
    j = 0
    while entry[j].ord > 0 do
      name+= entry[j]
      j+= 1
    end

    isFile = entry.unpack("x772L<L<")[0]
    
    if j > 0 then
      if isFile == 0 then
        dump(path + name + "/", target + "/" + name)
      else
        dumpFile(path + name, target + "/" + name)
      end
    else
      free pathBuf
      return
    end
  end
end
