Sequel.migration do
  up do
    alter_table(:flags) do
      add_column :mostsig_pos, :bigint
      add_column :leastsig_pos, :bigint
    end
    
    $db[:flags].all do |row|
      pos = row[:actual_position].unpack("L<L<")
      $db[:flags].where(:id => row[:id]).update(:mostsig_pos => pos[1], :leastsig_pos => pos[0])
    end
  end

  down do
    alter_table(:flags) do
      drop_column :mostsig_pos
      drop_column :leastsig_pos
    end
  end
end
