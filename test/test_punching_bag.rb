$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'lib/punching_bag'
require 'test/unit'

class TestPunchingBag < Test::Unit::TestCase

  def test_create_machine_and_run_command
    c = PunchingBag::Controller.new
		c[0].start
		c[0].run_command "cat /etc/passwd"
		c[0].terminate
  end

end
