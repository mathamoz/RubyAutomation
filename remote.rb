require 'rubygems'
require 'net/ssh'
require 'net/scp'
=begin
Class required by automate.rb used for handing the connection
to a server and running commands on it.
=end


class Remote
  def initialize(host, user, pass)
    @host = host
   	  begin
  	    @ssh = Net::SSH::start(host, user, :password => pass) 
  	  rescue Net::SSH::HostKeyMismatch => e
        puts "** Connecting to new host, remembering key: #{e.fingerprint}"
        e.remember_host!
        retry
      rescue Net::SSH::AuthenticationFailed => e
        raise "** Failed to authenticate to #{host}: #{e}"
      end
  end
  
  def execute(command)
    output = ""
    @ssh.open_channel do |ch|
      ch.request_pty do |ch, success|
		    raise "Unable to create pty on #{@host}!" if !success
        ch.exec command do |ch, success|
          raise "Failed to execute #{command} on #{@host}" if !success
          ch.on_data do |c, data|
            output << data
          end
        end
        ch.wait
      end
    end
    @ssh.loop
    return output
  end
  
  def put(local, remote)
	scp = @ssh.scp
	scp.upload!(local, remote) do |ch, name, received, total|
	  progress = format('%.2f', received.to_f / total.to_f * 100)
	  #print "#{message} ["
	  #print "=" * [(progress.to_f/10).to_i, 10].min
	  #print " " * [10-(progress.to_f/10.to_i, 0].max
	  #print "]" #{progress}%\r"
	  #if progress == '100.00'
	  #  print "\n"
	  #end
	  #STDOUT.flush
	end
  end
end
