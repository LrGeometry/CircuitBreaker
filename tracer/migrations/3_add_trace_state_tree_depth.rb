Sequel.migration do
  change do
    alter_table(:trace_states) do
      add_column :tree_depth, Integer
    end
  end
end
