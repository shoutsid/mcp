# frozen_string_literal: true

require "json"

require_relative "agents_fyi_mcp/client"
require_relative "agents_fyi_mcp/context"
require_relative "agents_fyi_mcp/rendering"
require_relative "agents_fyi_mcp/tools"
require_relative "agents_fyi_mcp/identity"
require_relative "agents_fyi_mcp/surface"
require_relative "agents_fyi_mcp/prompts"
require_relative "agents_fyi_mcp/resources"
require_relative "agents_fyi_mcp/server"

#
#
# Run:  lib/mcp/bin/agents-fyi-mcp        (stdio transport; the wrapper sets the bundle)
#       or `ruby lib/mcp/bin/agents-fyi-mcp`
# Env:  AGENTS_FYI_URL       default https://agents.shoutsid.fyi
#       AGENTS_FYI_API_KEY   required for submit/verify/outcome only
#       AGENTS_FYI_RECORD    set to `false` when this server's reads are a
#                            self-check and must not be counted as demand
module AgentsFyiMcp
  module Config
    module_function

    def base_url
      (ENV["AGENTS_FYI_URL"] || "https://agents.shoutsid.fyi").sub(%r{/+\z}, "")
    end

    def api_key
      (ENV["AGENTS_FYI_API_KEY"] || "").strip
    end

    def timeout
      Float(ENV["AGENTS_FYI_TIMEOUT"] || "25")
    end

    # Whether the reads this server makes count as *demand*. On by default, because
    # a caller's search is the only signal the service has about what people cannot
    # find. A self-check that drives this server — the harness that measures whether
    # a model reaches these tools — turns it off, because its searches are synthetic,
    # and a synthetic row does not look wrong; it looks like a user.
    #
    # An environment flag rather than a tool argument, deliberately: a model must not
    # be able to decide that its own lookup does not count.
    def record?
      !%w[0 false no].include?((ENV["AGENTS_FYI_RECORD"] || "").strip.downcase)
    end

    # One structured line per protocol request, on by default. The suite turns it off: 500
    # requests' worth of telemetry interleaved with a test runner's dots is noise, and nothing in
    # the suite asserts on it — the shape is one line of JSON with the method, tool and duration.
    def log?
      !%w[0 false no].include?((ENV["AGENTS_FYI_MCP_LOG"] || "").strip.downcase)
    end

    # The hosted endpoint's transport hardening. The host list is the public hostname the
    # deployment routes to this service; the origin list is empty because no browser is meant to
    # call it. `max_request_bytes` is a hard bound rather than the SDK's 4 MiB default.
    def mcp_hosts
      csv("AGENTS_FYI_MCP_HOSTS", %w[agents.shoutsid.fyi])
    end

    def mcp_origins
      csv("AGENTS_FYI_MCP_ORIGINS", [])
    end

    def max_request_bytes
      Integer(ENV["AGENTS_FYI_MCP_MAX_REQUEST_BYTES"] || (1024 * 1024))
    end

    def csv(name, default)
      value = (ENV[name] || "").split(",").map(&:strip).reject(&:empty?)
      value.empty? ? default : value
    end
  end

  module_function

  def client
    Client.new(
      base_url: Config.base_url,
      api_key: Config.api_key,
      timeout: Config.timeout,
      record: Config.record?,
    )
  end

  # A server for this process. The client is passed beside the tools because resources read
  # documents (`llms.txt`, the discovery document) that are not tool calls; the tools remain the
  # whole behaviour surface.
  def build(client: nil)
    client ||= self.client
    Server.new(tools: Tools.new(client), client: client)
  end

  def main
    build.run
  end
end
