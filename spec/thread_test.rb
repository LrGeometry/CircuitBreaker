require_relative "circuitbreaker_helper.rb"

RSpec.configure do |c|
  c.include CircuitBreakerHelper
end

RSpec.describe "threads" do
  it "works" do
    switch.load "threads.rb"

    program = switch.create_program do
      statics do
        field :value1, 0x456789AA
        reference, :value1_ptr, :value1
        field :value2, 0x11111111
        reference, :value2_ptr, :value2
        field :retval, 0xDEADBEEF
        reference :retval_ptr, :retval
        
        constant :length, 8
      end
      call(Bridges::memcpy, [:value2_ptr, :value1_ptr, :length], :retval_ptr)
    end
  end
end
