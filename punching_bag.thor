$:.unshift(File.join(File.dirname(__FILE__)))
require 'lib/punching_bag'

class X < Thor

  desc "start", "Start a vulnerable system"
  method_options :name => "ubuntu_606_dapper_x86"
  def start
    name = options[:name]
    puts "Starting vulnerable system: #{name}"
    controller = PunchingBag::Controller.new
    controller[name].start
  end
  
  desc "list", "List the vulnerable systems"
  def list
    puts "Listing vulnerable systems:"
    controller = PunchingBag::Controller.new
    controller.each { |vm| puts "#{vm.name}: #{vm.description}" }
  end


end
