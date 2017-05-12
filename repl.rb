require "pry"

require_relative "./dsl.rb"

exploit = "pegasus"
if ARGV.length > 0 then
  exploit = ARGV[0]
end

case exploit
when "pegasus"
  require_relative "./exploit/pegasus/remote.rb"
  Exploit::Pegasus.initialize.bind.pry
when "tracer" # not really an exploit, but still provides a switch interface
  require_relative "./tracer/tracer.rb"
  Tracer.initialize.bind.pry
else
end


