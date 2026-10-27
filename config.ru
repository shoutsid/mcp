# frozen_string_literal: true

# The hosted MCP endpoint, as a Rack application.
#
# `puma config.ru` is what the component's image runs. The stdio server is `bin/agents-fyi-mcp`
# and is unaffected by this file: a harness with a checkout keeps the transport it can measure,
# and this is for agents that have none.
require_relative "lib/agents_fyi_mcp/http_app"

run AgentsFyiMcp::HttpApp.new
