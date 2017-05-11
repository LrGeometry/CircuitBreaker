require "pry"

$exploitMap = {}

require_relative "./dsl.rb"
require_relative "./exploit/pegasus/remote.rb"

exploit = "pegasus"
if ARGV.length > 0 then
  exploit = ARGV[0]
end

if(!$exploitMap[exploit]) then
  raise "no such exploit '#{exploit}'"
end

$exploitMap[exploit].get_dsl.bind.pry
