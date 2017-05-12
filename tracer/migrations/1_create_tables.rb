Sequel.migration do
  change do
    create_table(:trace_states) do
      primary_key :id
      File :state

      foreign_key :parent_id, :trace_states, :on_delete => :cascade, :on_update => :cascade
    end

    create_table(:trace_pages) do
      primary_key :id
      File :header # sqlite is weird about 64-bit values, so this is safer
      File :data
    end

    create_join_table(:trace_state_id => :trace_states, :trace_page_id => :trace_pages)
    
    create_table(:memory_mapping_blocks) do
      primary_key :id
      File :header # again, 64-bit values. this is [offset, size, state, perms, pageInfo].pack("Q<*")
    end

    create_table(:flags) do
      primary_key :id
      String :name, :index => true
      File :actual_position, :index => true # 64-bit values again
    end
  end
end
