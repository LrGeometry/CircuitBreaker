module Tracer
  module HLE
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
