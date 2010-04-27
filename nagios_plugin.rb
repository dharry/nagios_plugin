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
  end

  def current_method
    caller.first[/:in \`(.*?)\'\z/, 1]
  end

  def parse(argv, args=[:H, :w, :c])
    o = {}
    parse = OptionParser.new
    args.each {|c|
      next if [:H, :w, :c, :C].index(c)
      parse.on("-#{c.to_s} value", 'value') {|v| o[c] = v }
    }
    parse.on("-w warning",  'threshold(%)') {|v| o[:w] = v.to_i }
    parse.on("-c critical", 'threshold(%)') {|v| o[:c] = v.to_i }
    parse.on("-H hostname", 'hostname')     {|v| o[:H] = v }
    parse.on("-C community", 'snmp community') {|v| o[:C] = v }
    parse.on("-V snmp version", 'snmp protocol version') {|v| o[:V] = v }
    parse.on("-m mib", 'snmp mib') {|v| o[:m] = v }
    parse.on("-d disk", 'disk label') {|v| o[:d] = v }

    begin
      parse.parse!(argv)
    rescue OptionParser::ParseError => e
      puts parse.help
      return nil
    else
      [:H, :w, :c].each{|opt|
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
  # memory(%) or swap(%)
  #  UCD-SNMP-MIB::memory
  # == Example
  # # create script(check_memory.rb)
  #   require 'nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.memory
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_memory.rb
  #  $ ruby check_memory.rb -H {hostname} -V {1|2c} -C {community} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #  define command {
  #    command_name  check_memory_rb
  #    command_line  $USER1$/check_memory.rb -H $HOSTADDRESS$ -V $ARG1$ -C $ARG2$ -w $ARG3$ -c $ARG4$
  #  }
  def memory
    mib = "UCD-SNMP-MIB::memory"
    host, snmpver, community, = @base[:H], @base[:V], @base[:C]
    st = IO.popen("snmpwalk -Os -v #{snmpver} -c #{community} #{host} #{mib} 2> /dev/null", "r").map

    if st.zero?
      return (check(nil) + Nagios::ErrMsg[0])
    end

    h = {}
    st.each {|line|
      elems = line.gsub(/\.0/,"").split
      h[elems[0]] = elems[3].to_f
    }
    h.symbolize_keys!

    case current_method
    when "memory"
      val = 0 if (h[:memTotalReal] - h[:memAvailReal]).ceil == 0 
      unless val == 0
        usedmem = (h[:memAvailReal] + h[:memBuffer] + h[:memCached])
        val = (((h[:memTotalReal] - usedmem) * 100) / h[:memTotalReal]).ceil
      end
      msg = "value=#{val}%, memTotalReal=#{h[:memTotalReal]}, memAvailReal=#{h[:memAvailReal]}"
    when "swap"
      val = 0 if (h[:memTotalSwap] - h[:memAvailSwap]).ceil == 0
      val ||= (((h[:memTotalSwap] - h[:memAvailSwap]) * 100) / h[:memTotalSwap]).ceil
      msg = "value=#{val}%, memTotalSwap=#{h[:memTotalSwap]}, memAvailSwap=#{h[:memAvailSwap]}"
    end

    retval = check(val) + [msg]
    return(retval)
  end

  alias swap memory

  # cpu(%)
  #   UCD-SNMP-MIB::systemStats
  # == Example
  # # create script(check_cpu.rb)
  #   require 'nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.cpu
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_cpu.rb
  #  $ ruby check_cpu.rb -H {hostname} -V {1|2c} -C {community} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #   define command{
  #     command_name  check_cpu_rb
  #     command_line  $USER1$/check_cpu.rb -H $HOSTADDRESS$ -V $ARG1$ -C $ARG2$ -w $ARG3$ -c $ARG4$
  #   }
  def cpu
    mib = "UCD-SNMP-MIB::systemStats"
    host, snmpver, community, = @base[:H], @base[:V], @base[:C]
    st = IO.popen("snmpwalk -Os -v #{snmpver} -c #{community} #{host} #{mib} 2> /dev/null", "r").map

    if st.zero?
      return (check(nil) + Nagios::ErrMsg[0])
    end

    h = {}
    st.each {|line|
      elems = line.gsub(/\.0/,"").split
      h[elems[0]] = elems[3].to_f
    }
    h.symbolize_keys!

    val = (h[:ssCpuUser] + h[:ssCpuSystem]).ceil
    msg = "value=#{val}%, ssCpuUser=#{h[:ssCpuUser]}, ssCpuSystem=#{h[:ssCpuSystem]}"

    if [h[:ssCpuUser], h[:ssCpuSystem]].index("")
      return check(nil) + ["#{Nagios::ErrMsg[2]} #{msg}"]
    end

    retval = check(val) + [msg]
    return retval
  end

  # disk(%)
  #   HOST-RESOURCES-MIB::hrStorageTable
  # == Example
  # # create script(check_disk1.rb)
  #   require 'nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.cpu
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_disk1.rb
  #  $ ruby check_disk1.rb -H {hostname} -V {1|2c} -C {community} -d {disk} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #   define command{
  #     command_name  check_disk1_rb
  #     command_line  $USER1$/check_disk1.rb -H $HOSTADDRESS$ -V $ARG1$ -C $ARG2$ -d $ARG3$ -w $ARG4$ -c $ARG5$
  #   }
  def disk1
    mib = "HOST-RESOURCES-MIB::hrStorageTable"
    host, snmpver, community, disk = @base[:H], @base[:V], @base[:C], @base[:d]
    st = IO.popen("snmpwalk -Os -v #{snmpver} -c #{community} #{host} #{mib} 2> /dev/null", "r").map

    if st.zero?
      return (check(nil) + Nagios::ErrMsg[0])
    end

    h = {}
    st.each {|line|
      elems = line.split
      if elems[3]
        h[elems[0]] = (elems[3] =~ /\D/) ? elems[3] : elems[3].to_i
      end
    }

    re = /hrStorageIndex/
    indexes = h.inject([]){|r,v| r << v[0].split(".")[1].to_i if v[0] =~ re; r }

    disks = {}
    indexes.each {|idx|
      key = "hrStorageDescr." + idx.to_s
      hrSDescr = h[key]
      disks[hrSDescr] = {
        :hrStorageSize => h["hrStorageSize.#{idx}"],
        :hrStorageUsed => h["hrStorageUsed.#{idx}"],
        :hrStorageAllocationUnits => h["hrStorageAllocationUnits.#{idx}"],
      }
    }

    # disk label not found
    unless disks.key?(disk)
      return (check(nil) + [Nagios::ErrMsg[1]])
    end

    # calc
    total_size = disks[disk][:hrStorageSize]
    total_used = disks[disk][:hrStorageUsed]
    allocation = disks[disk][:hrStorageAllocationUnits]

    total = (total_size * allocation / 1024)
    used  = (total_used * allocation / 1024)
    
    val = [used,total].index(0) ? 0 : (used * 100 / (total * 0.94)).truncate 
    msg = "disk=#{disk}, val=#{val}%, total=#{total}, used=#{used}"

    retval = check(val) + [msg]
    return(retval)
  end

  # disk(%)
  #   UCD-SNMP-MIB::dskEntry
  # == Example
  # # create script(check_disk2.rb)
  #   require 'nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.disk2
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_disk2.rb
  #  $ ruby check_disk2.rb -H {hostname} -V {1|2c} -C {community} -d {disk} -w {warning(%)} -c {critical(%)}
  #
  # # etc/objects/commands.cfg
  #   define command{
  #     command_name  check_disk2_rb
  #     command_line  $USER1$/check_disk2.rb -H $HOSTADDRESS$ -V $ARG1$ -C $ARG2$ -d $ARG3$ -w $ARG4$ -c $ARG5$
  #   }
  def disk2
    mib = "UCD-SNMP-MIB::dskEntry"
    host, snmpver, community, disk = @base[:H], @base[:V], @base[:C], @base[:d]
    st = IO.popen("snmpwalk -Os -v #{snmpver} -c #{community} #{host} #{mib} 2> /dev/null", "r").map

    if st.zero?
      return (check(nil) + Nagios::ErrMsg[0])
    end

    h = {}
    st.each {|line|
      elems = line.split
      if elems[3]
        h[elems[0]] = (elems[3] =~ /\D/) ? elems[3] : elems[3].to_i
      end
    }

    re = /dskIndex/
    indexes = h.inject([]){|r,v| r << v[0].split(".")[1].to_i if v[0] =~ re; r }

    disks = {}
    indexes.each {|idx|
      key = "dskPath." + idx.to_s
      dskPath = h[key]
      disks[dskPath] = {
        :dskDevice  => h["dskDevice.#{idx}"],
        :dskTotal   => h["dskTotal.#{idx}"],   
        :dskAvail   => h["dskAvail.#{idx}"],
        :dskUsed    => h["dskUsed.#{idx}"],
        :dskPercent => h["dskPercent.#{idx}"], 
      }
    }

    # disk label not found
    unless disks.key?(disk)
      return (check(nil) + [Nagios::ErrMsg[1]])
    end

    # calc
    total   = disks[disk][:dskTotal]
    avail   = disks[disk][:dskAvail]
    used    = disks[disk][:dskUsed]
    val     = disks[disk][:dskPercent]
    msg     = "disk=#{disk}, value=#{val}%, dskTotal=#{total}, dskAvail=#{avail}, dskUsed=#{used}"
  
    retval = check(val) + [msg]
    return(retval)
  end

  # LoadAverage(1,5,15)
  #   UCD-SNMP-MIB::laLoad.{1,2,3}
  # == Example
  # # create script(check_loadavg.rb)
  #   require 'nagios_plugin'
  #   nag = NagiosPlugin.new
  #   if nag.parse(ARGV)
  #     status, status_msg, verbos_msg = nag.loadavg(5)
  #     puts "#{File.basename(__FILE__)} - #{status_msg} | #{verbos_msg}" 
  #     exit(status)
  #   end
  #
  # # libexec/check_disk2.rb
  #  $ ruby check_loadavg.rb -H {hostname} -V {1|2c} -C {community} -w {warning(0.00)} -c {critical(0.00)}
  #
  # # etc/objects/commands.cfg
  #  define command{
  #    command_name  check_loadavg_rb
  #    command_line  $USER1$/check_loadavg.rb -H $HOSTADDRESS$ -V $ARG1$ -C $ARG2$ -w $ARG3$ -c $ARG4$
  #  }
  def loadavg(avg=5)
    key = ((avg == 1) ? 1 : (avg == 5 ? 2 : 3))
    mib = "UCD-SNMP-MIB::laLoad"
    host, snmpver, community = @base[:H], @base[:V], @base[:C]
    st = IO.popen("snmpwalk -Os -v #{snmpver} -c #{community} #{host} #{mib} 2> /dev/null", "r").map

    if st.zero?
      return (check(nil) + Nagios::ErrMsg[0])
    end

    h = st.inject({}) {|r,v|
          elems = v.gsub(/laLoad\./,"").split
          r[elems[0].to_i] = elems[3].to_f
          r
        }

    val = h[key]
    msg = "laLoad.1=#{h[1]}, laLoad.5=#{h[2]}, laLoad.15=#{h[3]}"

    return check(val) + [msg]
  end
end

