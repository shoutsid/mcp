# frozen_string_literal: true

# The MCP server's own bundle.
#
# **It is a bundle of its own because the component is a client.** `mcp` is the SDK the
# server is built on, and the service's image deliberately installs without `development
# test` and ships no MCP surface: an SDK in the container that answers the internet is a
# dependency nothing in the application loads, and a client is not part of the service
# (`docs/refactor/adr/0003-components-are-the-module-root.md`). The root `Gemfile.lock`
# is asserted to carry no `mcp` gem, so adding one there fails the suite rather than
# quietly coupling the two.
source "https://rubygems.org"

gem "mcp", "~> 1.8"
# Both are for the hosted endpoint in Phase 6: the SDK's Streamable HTTP transport is a
# Rack application, and puma serves it. They are pinned here rather than added later so
# the component keeps one lockfile.
gem "puma", "~> 8.0"
gem "rack", "~> 3.1"

# The suite runs on this interpreter and needs no Rails, so minitest is the whole test
# dependency. It is in the test group because the image installs without it.
group :development, :test do
  gem "minitest", "~> 6.0"
end
