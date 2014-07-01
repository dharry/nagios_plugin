#!/usr/bin/ruby

require 'optparse'

class Array
  def zero?
    self.size == 0 ? true : false
  end
end

#It borrowed from activesupport
class Hash
  # Return a new hash with all keys converted to strings.
  def stringify_keys
    inject({}) do |options, (key, value)|
      options[key.to_s] = value
      options
    end
  end
  
  # Destructively convert all keys to strings.
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end
  
  # Return a new hash with all keys converted to symbols.
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end
  
  # Destructively convert all keys to symbols.
  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end
end

module Nagios
  Status = [
    [0, "OK"],
    [1, "Warning"],
    [2, "Critical"],
    [3, "Unknown"],
  ]
  ErrMsg = [
    "fatal error encountered during command execution",
    "disk label not found",
    "failed to get system resources",
  ]
end

class NagiosBase
  include Nagios

  def initialize
    @base = Hash.new
    @xe = "xe"
  end

  def current_method
    caller.first[/:in \`(.*?)\'\z/, 1]
  end

  def parse(argv)
    o = {}
    parse = OptionParser.new
    parse.on("-w warning",  'threshold(%)') {|v| o[:w] = v.to_i }
    parse.on("-c critical", 'threshold(%)') {|v| o[:c] = v.to_i }
    parse.on("-H xenserver", 'xenserver')     {|v| o[:H] = v }
    parse.on("-P passwdfile", 'password file') {|v| o[:P] = v }
    parse.on("-I uuid", 'uuid') {|v| o[:I] = v }

    begin
      parse.parse!(argv)
    rescue OptionParser::ParseError => e
      puts parse.help
      return nil
    else
      [:H, :w, :c, :P, :I].each{|opt|
        unless o[opt]
          puts parse.help
          return nil
        end
      }
    end
    @base = o
  end

  def check(val)
    ret = val ? Nagios::Status[0] : Nagios::Status[3]
    if val
      ret = Nagios::Status[1] if val > @base[:w]
      ret = Nagios::Status[2] if val > @base[:c]
    end
    return ret
  end
end

class NagiosPlugin < NagiosBase
  # xe_vm_vcpu(%)
  # == Example
  # # create script(check_xe_vm_vcpu.rb)
  #   require 'xe_nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.xe_vm_vcpu
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_xe_vm_vcpu.rb
  #  $ ruby check_xe_vm_vcpu.rb -H {xenserver}  -P {passwdfile} -I {uuid} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #  define command {
  #    command_name  check_xe_vcpu
  #    command_line  $USER1$/check_xe_vm_vcpu.rb -H $HOSTADDRESS$ -P $ARG1$ -I $ARG2$ -w $ARG3$ -c $ARG4$
  #  }
  def xe_vm_vcpu
    st = IO.popen("#{@xe} -s #{@base[:H]} -pwf #{@base[:P]} vm-param-get uuid=#{@base[:I]} param-name=VCPUs-utilisation 2> /dev/null", "r").map
    
    if st.zero? 
      return (check(nil) + [Nagios::ErrMsg[0]])
    end
    if st[0] == "\n"
      return (check(nil) + [Nagios::ErrMsg[0]])
    end

    val = 0.000
    vcpus = st.to_s.split(";")
    vcpus.each {|vcpu| val += vcpu.split(":")[1].to_f }
    val = ((val * 100) / vcpus.size)
    msg = "total_cpu_usage=#{val}%, VCPUs-utilisation(#{st.to_s.chomp})"
    retval = check(val) + [msg]
    return(retval)
  end

  # xe_vm_memory(%)
  # == Example
  # # create script(check_xe_vm_memory.rb)
  #   require 'xe_nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.xe_vm_memory
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_xe_vm_memory.rb
  #  $ ruby check_xe_vm_memory.rb -H {xenserver}  -P {passwdfile} -I {uuid} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #  define command {
  #    command_name  check_xe_memory
  #    command_line  $USER1$/check_xe_vm_vcpu.rb -H $HOSTADDRESS$ -P $ARG1$ -I $ARG2$ -w $ARG3$ -c $ARG4$
  #  }
  def xe_vm_memory

    query = "vm-data-source-query"
    datasource = %w(data-source=memory data-source=memory_internal_free)
   
    # real memory
    st = IO.popen("#{@xe} -s #{@base[:H]} -pwf #{@base[:P]} #{query} #{datasource[0]} uuid=#{@base[:I]} 2> /dev/null", "r").map
    if st.zero?
      return (check(nil) + [Nagios::ErrMsg[0]])
    end
    total_mem = (st[0].to_i / (1024 * 1024)) # megabytes
    
    # free memory
    st = IO.popen("#{@xe} -s #{@base[:H]} -pwf #{@base[:P]} #{query} #{datasource[1]} uuid=#{@base[:I]} 2> /dev/null", "r").map
    if st.zero?
      return (check(nil) + [Nagios::ErrMsg[0]])
    end
    free_mem = (st[0].to_i / 1024) # megabytes
    
    val = (100 * (total_mem - free_mem) / total_mem)

    msg = "memory_usage=#{val}%, memory=#{total_mem}mb, memory_internal_free=#{free_mem}mb"
    retval = check(val) + [msg]
    return(retval)
  end

end

