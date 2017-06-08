Sequel.migration do
  up do
    alter_table(:memory_mapping_blocks) do
      add_column :mostsig_offset, :bigint
      add_column :leastsig_offset, :bigint
      add_column :mostsig_endpos, :bigint
      add_column :leastsig_endpos, :bigint
    end
    
    $db[:memory_mapping_blocks].all do |row|
      header = row[:header].unpack("Q<Q<")
      offset = [header[0]].pack("Q<").unpack("L<L<")
      endpos = [header[0] + header[1]].pack("Q<").unpack("L<L<")
      $db[:memory_mapping_blocks].where(:id => row[:id]).update(
        :mostsig_offset => offset[1], :leastsig_offset => offset[0],
        :mostsig_endpos => endpos[1], :leastsig_endpos => endpos[0])
    end
  end

  down do
    alter_table(:memory_mapping_blocks) do
      drop_column :mostsig_offset
      drop_column :leastsig_offset
      drop_column :mostsig_endpos
      drop_column :leastsig_endpos
    end
  end
end
