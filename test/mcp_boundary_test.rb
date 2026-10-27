# frozen_string_literal: true

require_relative "test_helper"

# The boundary that makes this component a *client*.
#
# `lib/mcp` carries no `package.yml`, so it is not a package of the application, and its bundle is
# its own, so the SDK never enters the container that answers the internet. The two service-side
# halves of this agreement — the service's `Gemfile.lock` carrying no `mcp` gem, and the service's
# `.dockerignore` keeping the client out of the image — need both repositories and live in
# `test/contracts/mcp/boundary_test.rb` in the service checkout.
class McpBoundaryTest < McpTest
  def test_the_gemfile_that_does_carry_it_is_this_component_s_own
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))
    assert_match(/^gem "mcp"/, gemfile)
    assert File.exist?(File.expand_path("../Gemfile.lock", __dir__))
  end

  def test_the_component_is_not_a_package
    refute File.exist?(File.expand_path("../package.yml", __dir__)),
      "lib/mcp became a package: the client boundary is what keeps it out of the service"
  end
end
