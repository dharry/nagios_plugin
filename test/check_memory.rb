#!/usr/bin/ruby

$LOAD_PATH.push(File.expand_path(File.dirname(__FILE__)))
require 'nagios_plugin'

nag = NagiosPlugin.new
if nag.parse(ARGV)
  status, status_msg, verbos_msg = nag.memory
  puts "#{File.basename(__FILE__)} - #{status_msg} #{verbos_msg}"
  exit(status)
end
