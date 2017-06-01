Sequel.migration do
  change do
    create_table(:comments) do
      primary_key :id
      column :mostsig_pos, :bigint
      column :leastsig_pos, :bigint
      column :context, :varchar
    end
  end
end
