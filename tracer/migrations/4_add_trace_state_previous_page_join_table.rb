Sequel.migration do
  change do
    create_table(:trace_state_previous_pages) do
      foreign_key :trace_state_id, :trace_states, :null => false
      foreign_key :trace_page_id, :trace_pages, :null => false
      primary_key [:trace_state_id, :trace_page_id]
      add_index [:trace_state_id, :trace_page_id]
    end

    alter_table(:trace_pages) do
      add_column :dirty, FalseClass, :index => true
    end
  end
end
