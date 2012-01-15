$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'lib/punching_bag'
require 'test/unit'

class TestPunchingBag < Test::Unit::TestCase

  def test_connect
    c = PunchingBag::Controller.new
    assert c.connect.kind_of? Fog::Compute::AWS::Real
  end

end
