Sequel.migration do
  change do
    alter_table(:comments) do
      add_index [:mostsig_pos, :leastsig_pos], :unique => true
    end
  end
end
