require 'rubygems'
require 'net/ssh'
require 'net/http'
require 'aws-sdk'

module PunchingBag

class Controller

  include Enumerable

  #
  # Takes: Nothing
  #
  # Returns: Nothing
  #
  # Notes: Sets up a list of Machine objects, acts as an enumerable object.
  #
  def initialize
    @basedir = File.join(File.dirname(__FILE__), "..")

    # Grab the configuration
    @pb_config = YAML::load(File.open("#{@basedir}/config/pb_config.yml"))

    # Load the list of machines into an array of Machine Objects
    machine_config_list = YAML::load(File.open("#{@basedir}/config/machines.yml"))
    #puts "DEBUG: Machine config: #{machine_config_list}"

    # Set up the EC2 connection
    @ec2 = AWS::EC2.new(
      :access_key_id => @pb_config['amazon_access_key'],
      :secret_access_key => @pb_config['amazon_secret_access_key'] 
    )

    # Parse the configuration array
    @machines = []
    machine_config_list.each do |machine_config|
      #puts "DEBUG: Parsing config: #{machine_config}"
      machine_config['ec2'] = @ec2
      machine_config['key_dir'] = File.join(@basedir, "keys")
      machine_config['config_dir'] = File.join(@basedir, "config")
      @machines << PunchingBag::Machine.new(machine_config)
    end

  end

  #
  # Takes: String or Integer 
  # 
  # Returns: VulnMachine or nil
  #
  # Notes: Helps this object act like an array
  #
  def [](x)
    if x.kind_of? String
      @machines.each {|m| return m if m.name == x }
    elsif x.kind_of? Integer
      @machines[x]
    end
  end

  #
  # Takes: Nothing
  #
  # Returns: Nothing
  #
  # Notes: Implements each so this object is enumerables
  #
  def each
    @machines.each { |x| yield x }
  end

end

# 
# This class represents a (vulnerable) machine. We implement methods here that
# make it act like a vm. Currently handles the EC2 connection & all reqs of that
# connection.
#
class Machine

  attr_accessor :name, :user, :type, :id, :description

  #
  # Takes: a config hash with configuration information (see the controller)
  #
  # Returns: Nothing
  #
  # Notes: Implements each so this object is enumerables
  #
  def initialize(config)
    @name = config['name']
    @type = config['type']
    @id = config['id']
    @description = config['description']
    @user = config['user']
    @key_dir = config['key_dir']
    @config_dir = config['config_dir']
    @ec2 = config['ec2']
    @started = false

    # We'll get these when the instance is started
    @key_pair = nil
    @security_group = nil
    @instance = nil
  end
  
  #
  # Takes: Nothing
  #
  # Returns: Nothing
  #
  # Notes: Sets up keypair, security group, and an instance. Runs a command to
  # verify that the system is actually started.
  #
  def start

    # Generate a key pair
    key_pair_name = "#{@name}_#{Time.now.to_i}"
    @key_pair = @ec2.key_pairs.create(key_pair_name)
    puts "Generated keypair #{@key_pair.name}, fingerprint: #{@key_pair.fingerprint}"

    # Write the keyfile out
    File.open(File.join(@key_dir,key_pair_name), "w").write(@key_pair.private_key)

    # Set up the security group
    @security_group = @ec2.security_groups.create("#{@name}_#{Time.now.to_i}")
    @security_group.authorize_ingress(:tcp, 22, "0.0.0.0/0")
    puts "Using security group: #{@security_group.name}"

    # Run the instance
    @instance = @ec2.instances.create(
      :image_id => @id,
      :key_pair => @key_pair,
      :security_groups => @security_group
    )
    
    sleep 1 until @instance.status != :pending

    # Return unless we're running
    puts "Launched instance #{@instance.id}, status: #{@instance.status}"
    puts "The system can be found at: #{@instance.ip_address}"
    exit 1 unless @instance.status == :running

    # Can safely say we've started here
    @started = true

    # Write the instance id out to a config file so we can stop it later
    File.open(File.join(@config_dir, "running_machines.yml"),"a").write("instance_id: #{@instance.id}")

    begin
      Net::SSH.start(@instance.ip_address, @user, :key_data => [@key_pair.private_key]) do |ssh|
        #puts "Running 'uname -a' on the instance yields:"
        puts "System info: #{ssh.exec!("uname -a")}"
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 1
      retry
    end
    
    puts "Connect to this box with: ssh -i #{@key_dir}/#{key_pair_name} #{@user}@#{@instance.ip_address}"
  end

  #
  # Takes: String to run on the remote system
  #
  # Returns: true if successful, false if not
  #
  # Notes: 
  #
  def run_command(command)
    return false unless @started
    begin
      Net::SSH.start(@instance.ip_address, @user, :key_data => [@key_pair.private_key]) do |ssh|
        puts "Running '#{command}' on the instance yields:"
        puts ssh.exec!(command)
        return true
      end
    rescue SystemCallError, Timeout::Error => e
      # port 22 might not be available immediately after the instance finishes launching
      sleep 1
      retry
    end
    return false
  end

  #
  # Takes: Nothing
  #
  # Returns: true if successful, false if not
  #
  # Notes: 
  #
  def terminate
    return false unless @started
    begin 
      [@instance, @security_group, @key_pair].compact.each(&:delete)
    rescue
      return false
    end
    return true
  end

end

end
