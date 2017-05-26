def load_flags(file, offset)
  Sequel::Model.db.transaction do
    file.each do |line|
      if line.start_with? " 00000001:" then
        addr = line[10, 16].to_i(16) + offset
        name = line[33..-1].strip
        
        if name.start_with?("nullsub_") || name.start_with?("def_") then
          next
        end
        
        flag = Flag.new
        flag.position = addr
        flag.name = name
        flag.save
      end
    end
  end
end
