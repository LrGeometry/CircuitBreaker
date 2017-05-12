require "bundler/setup"
require "websocket-eventmachine-server"
require "thread"

require_relative "../dsl.rb"
require_relative "../exploit/pegasus/remote.rb"

Exploit::Pegasus.initialize

module CircuitBreakerHelper
  def switch
    $dsl
  end

  def find_blank_region(size)
    memInfo = switch.new Types::MemInfo
    pageInfo = switch.new Types::PageInfo
    begin
      ptr = switch.main_addr
      SVC::QueryMemory.call(memInfo, pageInfo, ptr)
      while memInfo.arrow(:memoryPermissions) > 0 || memInfo.arrow(:pageSize) < size do
        ptr = ptr + memInfo.arrow(:pageSize)
        SVC::QueryMemory.call(memInfo, pageInfo, ptr)
      end
      return ptr
    ensure
      memInfo.free
      pageInfo.free
    end
  end

  def malloc_aligned(size, alignment=0x2000)
    buf = switch.malloc size+alignment
    return buf + ((alignment-(buf.value%alignment))%alignment)
  end
end
