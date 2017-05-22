Sequel.migration do
  change do
    alter_table(:trace_states) do
      add_column :instruction_count, Integer, :default => 0
    end
  end
end
