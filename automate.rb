#!/usr/bin/env ruby
#################
## Automate the running of commands on a list of servers.
#################

require 'rubygems'
require 'highline/import'
require 'optparse'
require 'ostruct'
require 'remote.rb'
require 'pp'
require 'enumerator'

# Global Variables
@threads = []
@ithreads = Thread.list.count + 1

@hosts = []
@commands = []

@tStamp = Time.now
@tStamp = @tStamp.strftime("%Y-%m-%d-%H:%M:%S")

@errors = ''

options = OpenStruct.new
options.commands = 'commands.conf'

# Parse options
opts = OptionParser.new do | opts |
  opts.banner = "Usage: ./automate.rb [options]"
  opts.separator ""
  opts.separator "Specific Options:"
  
  opts.on("-c", "--commands", "File containing commands to run.") do | v | 
    options.commands = v || ''
  end
  opts.on("-H", "--hosts", "File containing hosts to connect to.") do | v | 
    options.hosts = v || ''
  end
  opts.separator ""
  opts.on("-h", "--help", "Show this stuff...") { puts opts; exit }
end.parse!

# Utility Functions
def check_file(file)
  if not File.exists?(file)
    raise "#{file} does not exist!"
    abort
  end
  return true
end

def load_from_file(file, into)
  if check_file(file)
    File.open(file, 'r') do | myFile |
      myFile.each do | line |
        into << line.chomp
      end
    end
  end
end

def check_creds(host, user, pass)
  begin
    @ssh = Net::SSH::start(host, user, :password => pass)
  rescue Net::SSH::HostKeyMismatch => e
    puts "** Connecting to new host, remembering key: #{e.fingerprint}"
    e.remember_host!
    retry
  rescue Net::SSH::AuthenticationFailed => e
    puts "Credentials check failed!  Aborting to prevent account lock."
    return false
  end
end

# Load the config files
#if !options.hosts then @hosts_file = 'hosts.conf' end
#if !options.commands then @commands_file = 'commands.conf' end
@hosts_file = 'hosts.conf'
@commands_file = 'commands.conf'

puts "Hosts: #{@hosts_file}"
puts "Commands: #{@commands_file}"

load_from_file(@hosts_file, @hosts)
load_from_file(@commands_file, @commands)

# Prompt for user and pass
@user ||=
  ask("Username: ")
@pass ||=
  ask("Password: ") { |q| q.echo = '*' }

# Check the provided credentials.
if !check_creds(@hosts[0], @user, @pass)
  exit
end

# Make a new directory for spitting results to
Dir::mkdir(@tStamp)
begin
  File.unlink('latest')
rescue
end
File.symlink(@tStamp, 'latest')

spawned = 0

#@hosts.each do | host |
@hosts.each_slice(10) do | host |
  @threads << Thread.new(host) { | myHosts |
      myHosts.each do | myHost |
      begin
        File.open("#{@tStamp}/#{myHost}", 'w') do | myFile |
          server = Remote.new(myHost, @user, @pass)
          puts "** Running commands on #{myHost}"
          @commands.each do | command_string |
            if command_string.index('?')
              desc = command_string.split('?')[0]
              command = command_string.split('?')[1].strip
            else
              desc = command_string
              command = command_string
            end
		  
            if command.match(/^put/)
		      local = command.split(' ')[1]
		      remote = command.split(' ')[2]
		      result = server.put(local, remote)
		    else
              result = server.execute(command)
		    end
		  
            if !result
		      result = "OK"
		    end
		    myFile << "#{desc}:\n#{result}\n"
          end
	    end
    rescue StandardError => e
      @errors << "Problem connecting to #{myHost}: #{e}\n"
      next
    end
    end
  }

  spawned += 1

  if spawned > 25
   while Thread.list.count > 25
    puts "*** Pausing before spawning more threads..."
    sleep 5
   end
   spawned = 0
  end
end

# Status thread
@threads << Thread.new() {
  while Thread.list.count > @ithreads
    running = Thread.list.count - @ithreads
    puts "** Waiting on #{running*10} session(s) to finish..."
    if running == 0
      abort
    end
    sleep 5
  end
}

@threads.each { | myThreads | myThreads.join(300) }

File.open("#{@tStamp}/errors", 'w') do | eFile |
  eFile << @errors
end

puts "All Done!"
