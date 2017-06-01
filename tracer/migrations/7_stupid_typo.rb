Sequel.migration do
  change do
    alter_table(:comments) do
      rename_column :context, :content
    end
  end
end
