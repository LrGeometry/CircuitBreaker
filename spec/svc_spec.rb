require_relative "circuitbreaker_helper.rb"

# describes how to use some of the SVCs for n00bs like me

RSpec.configure do |c|
  c.include CircuitBreakerHelper
end

RSpec.describe "svcQueryMemory" do
  it "reports browser binary pages as executable" do
    memInfo = switch.new Types::MemInfo
    pageInfo = switch.new Types::PageInfo
    begin
      expect(SVC::QueryMemory.call(memInfo, pageInfo, switch.main_addr)).to eq(ResultCode::OK)
      expect(memInfo.arrow(:memoryPermissions)).to eq 0b101 # RX
    ensure
      memInfo.free
      pageInfo.free
    end
  end

  it "reports the JavaScript heap as read-write" do
    memInfo = switch.new Types::MemInfo
    pageInfo = switch.new Types::PageInfo
    buf = switch.malloc 0x1000
    begin
      expect(SVC::QueryMemory.call(memInfo, pageInfo, buf)).to eq(ResultCode::OK)
      expect(memInfo.arrow(:memoryPermissions)).to eq 0b011 # RW
    ensure
      memInfo.free
      pageInfo.free
      buf.free
    end
  end
end

RSpec.describe "svcSleepThread" do
  it "blocks for 1 second" do
    t = Time.now
    SVC::SleepThread.call(1000000000) # 1 second
    t2 = Time.now
    expect(t2-t).to be_within(0.4).of(1)
  end
end

RSpec.describe "svcGetCurrentProcessorNumber" do
  it "returns a number in [0,4)" do
    expect(SVC::GetCurrentProcessorNumber.call).to be_between(0, 3).inclusive
  end

  it "returns the same number every time (JS is always in the same thread)" do
    number = SVC::GetCurrentProcessorNumber.call
    5.times do
      expect(SVC::GetCurrentProcessorNumber.call).to eq number
    end
  end
end

RSpec.describe "svcProtectMemory" do
  it "can go from RW -> R -> RW" do
    size = 0x2000
    region = malloc_aligned size
    begin
      expect(region.query_memory.memoryPermissions).to eq(3)
      SVC::ProtectMemory.call(region, size, 1)
      expect(region.query_memory.memoryPermissions).to eq(1)
      SVC::ProtectMemory.call(region, size, 3)
      expect(region.query_memory.memoryPermissions).to eq(3)
    ensure
      region.free
    end
  end
end

RSpec.describe "svcs for memory mirrors" do
  it "can create and close a basic memory mirror" do
    region = switch.malloc 0x2000
    mirror = switch.new Types::Handle
    begin
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 3)).to eq(ResultCode::OK)
      expect(SVC::CloseHandle.call(mirror.deref)).to eq(ResultCode::OK)
    ensure
      region.free
      mirror.free
    end
  end
  
  it "will not allow mapping to low addresses" do
    region = switch.malloc 0x2000
    mirror = switch.new Types::Handle
    begin
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 3)).to eq(ResultCode::OK)
      handle = mirror.deref
      map = switch.make_pointer(0x2000)
      expect(map.query_memory.memoryPermissions).to eq(0)
      begin
        expect(SVC::MapMemoryMirror.call(handle, map, 0x2000, 3)).to eq(ResultCode.get(0xDC01))
      ensure
        expect(SVC::CloseHandle.call(handle)).to eq(ResultCode::OK)
      end
    ensure
      region.free
      mirror.free
    end
  end

  it "will not allow unmapping of mirrors that have not been mapped" do
    region = switch.malloc 0x2000
    mirror = switch.new Types::Handle
    begin
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 3)).to eq(ResultCode::OK)
      handle = mirror.deref
      map = switch.make_pointer(0x2000)
      expect(map.query_memory.memoryPermissions).to eq(0)
      begin
        expect(SVC::UnmapMemoryMirror.call(handle, map, 0x2000)).to eq(ResultCode.get(0xdc01))
      ensure
        expect(SVC::CloseHandle.call(handle)).to eq(ResultCode::OK)
      end
    ensure
      region.free
      mirror.free
    end
  end
  
  it "can be mapped and unmapped and changes permissions" do
    region = switch.malloc 0x2000
    mirror = switch.new Types::Handle
    begin
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 3)).to eq(ResultCode::OK)
      handle = mirror.deref
      map = find_blank_region 0x2000
      expect(map.query_memory.memoryPermissions).to eq(0)
      begin
        expect(SVC::MapMemoryMirror.call(handle, map, 0x2000, 3)).to eq(ResultCode::OK)
        begin
          expect(region.query_memory.memoryPermissions).to eq(3)
          expect(map.query_memory.memoryPermissions).to eq(3)
        ensure
          expect(SVC::UnmapMemoryMirror.call(handle, map, 0x2000)).to eq(ResultCode::OK)
        end
        expect(region.query_memory.memoryPermissions).to eq(3)
        expect(map.query_memory.memoryPermissions).to eq(0)
      ensure
        expect(SVC::CloseHandle.call(handle)).to eq(ResultCode::OK)
      end
    ensure
      region.free
      mirror.free
    end
  end

  it "reprotects the source region" do
    region = malloc_aligned 0x2000
    mirror = switch.new Types::Handle
    begin
      expect(region.query_memory.memoryPermissions).to eq(3)
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 1)).to eq(ResultCode::OK)
      expect(region.query_memory.memoryPermissions).to eq(1)
      handle = mirror.deref
      map = find_blank_region 0x2000
      expect(map.query_memory.memoryPermissions).to eq(0)
      begin
        expect(SVC::MapMemoryMirror.call(handle, map, 0x2000, 1)).to eq(ResultCode::OK)
        begin
          expect(region.query_memory.memoryPermissions).to eq(1)
          expect(map.query_memory.memoryPermissions).to eq(3)
        ensure
          expect(SVC::UnmapMemoryMirror.call(handle, map, 0x2000)).to eq(ResultCode::OK)
        end
        expect(region.query_memory.memoryPermissions).to eq(1)
        expect(map.query_memory.memoryPermissions).to eq(0)
        expect(SVC::ProtectMemory.call(region, 0x2000, 3)).to eq(ResultCode::OK)
        expect(region.query_memory.memoryPermissions).to eq(3)
      ensure
        expect(SVC::CloseHandle.call(handle)).to eq(ResultCode::OK)
      end
    ensure
      region.free
      mirror.free
    end
  end
  
  it "properly mirrors memory reads and writes" do
    rng = Random.new
    testString = rng.bytes(0x2000)
    
    region = switch.malloc 0x2000
    mirror = switch.new Types::Handle
    begin
      region.write(testString)
      expect(region.read(0x2000)).to eq(testString)
      
      expect(SVC::CreateMemoryMirror.call(mirror, region, 0x2000, 3)).to eq(ResultCode::OK)
      handle = mirror.deref
      map = find_blank_region 0x2000
      expect(map.query_memory.memoryPermissions).to eq(0)
      begin
        expect(SVC::MapMemoryMirror.call(handle, map, 0x2000, 3)).to eq(ResultCode::OK)
        begin
          expect(map.query_memory.memoryPermissions).to eq(3)
          expect(map.read(0x2000)).to eq(testString)
          expect(region.read(0x2000)).to eq(testString)
          
          testString = rng.bytes(0x2000)
          map.write(testString)
          expect(map.read(0x2000)).to eq(testString)
          expect(region.read(0x2000)).to eq(testString)
          
          testString = rng.bytes(0x2000)
          region.write(testString)
          expect(map.read(0x2000)).to eq(testString)
          expect(region.read(0x2000)).to eq(testString)
        ensure
          expect(SVC::UnmapMemoryMirror.call(handle, map, 0x2000)).to eq(ResultCode::OK)
        end
      ensure
        expect(SVC::CloseHandle.call(handle)).to eq(ResultCode::OK)
      end
    ensure
      region.free
      mirror.free
    end
  end
end
