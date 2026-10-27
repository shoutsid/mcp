# frozen_string_literal: true

# The MCP server's whole suite, on the component's own bundle:
# `bundle exec ruby -Ilib -Itest test/all_test.rb` from this repository's root, or
# `./scripts/dev.sh mcp` from the service checkout.
%w[
  mcp_tools_test
  mcp_tools_golden_test
  mcp_profile_tools_test
  mcp_transport_test
  mcp_prompts_resources_test
  mcp_boundary_test
  mcp_http_test
].each { |file| require_relative file }
