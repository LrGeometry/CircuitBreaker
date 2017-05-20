require_relative "../ipc_switch.rb"

module Tracer
  module HLE
    class Kernel
      def initialize(pg_state)
        @pg_state = pg_state
        @handles = {}
        @handle_no = 0x20000
        @ports = {}
        @ports["sm:"] = Tracer::HLE::ServiceManager.new(@pg_state, self)
      end
      
      def invoke_svc(no)
        case no
        when 0x1F
          svc_connect_to_port()
        when 0x21
          svc_send_sync_request()
        when 0x22
          svc_send_sync_request_by_buf()
        end
      end
      
      def svc_connect_to_port
        name = @pg_state.uc.mem_read(@pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X1), 8).unpack("Z8")[0]
        if @ports[name] then
          handle = Handle.new(@handle_no, :session, @ports[name].create_session)
          @handles[handle.id] = handle
          @handle_no+= 1
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, 0) # OK
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X1, handle.id)
        else
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, 0xf201) # no such port, module Kernel
        end
      end

      def svc_send_sync_request
        handle_id = @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X0)
        if @handles[handle_id] && @handles[handle_id].type == :session then
          handle = @handles[handle_id]
          buffer = @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_TPIDRRO_EL0)
          size = 0x100
          message = @pg_state.uc.mem_read(buffer, size)
          begin
            response = handle.object.send_message(IPC::IPCMessage.unpack(StringIO.new(message)))
            @pg_state.uc.mem_write(buffer, response.pack)
          rescue Fixnum => e # error codes
            @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, e)
          end
        else
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, 0xe401) # invalid handle, module Kernel
        end
      end
      
      def svc_send_sync_request_by_buf
        handle_id = @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X2)
        if @handles[handle_id] && @handles[handle_id].type == :session then
          handle = @handles[handle_id]
          buffer = @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X0)
          size = @pg_state.uc.reg_read(Unicorn::UC_ARM64_REG_X1)
          message = @pg_state.uc.mem_read(buffer, size)
          begin
            response = handle.object.send_message(IPC::IPCMessage.unpack(StringIO.new(message)))
            @pg_state.uc.mem_write(buffer, response.pack)
          rescue Fixnum => e # error codes
            puts "error in session handler"
            @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, e)
          end
        else
          @pg_state.uc.reg_write(Unicorn::UC_ARM64_REG_X0, 0xe401) # invalid handle, module Kernel
        end
      end
      
      Handle = Struct.new("Handle", :id, :type, :object)
    end

    class ServiceManager
      def initialize(pg_state, kernel)
        @pg_state = pg_state
        @kernel = kernel
      end

      def create_session
        Session.new(self)
      end

      class Session
        def initialize(sm)
          @sm = sm
        end

        def send_message(msg)
          cmd_id = msg.get_data.unpack("L<L<Q<")[2]
          case cmd_id
          when 0x00 # Initialize
            handle_initialize(msg)
          when 0x01 # GetService
            handle_get_service(msg)
          else
            raise 0xFFFF
          end
        end

        def handle_initialize(msg)
        end

        def handle_get_service(msg)
          
        end
      end
    end
  end
end
