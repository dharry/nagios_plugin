#!/usr/bin/ruby

$LOAD_PATH.push(File.expand_path(File.dirname(__FILE__)))
require 'xe_nagios_plugin'

nag = NagiosPlugin.new
if nag.parse(ARGV)
  status, status_msg, verbos_msg = nag.xe_vm_vcpu
  puts "#{status_msg} - #{verbos_msg}"
  exit(status)
end

