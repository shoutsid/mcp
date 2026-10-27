# frozen_string_literal: true

require "json"
require "mcp"

require_relative "identity"
require_relative "prompts"
require_relative "resources"
require_relative "surface"

module AgentsMcp
  # The MCP server, on the official Ruby SDK.
  #
  # The SDK owns the protocol: the handshake, the tool list, the call, pagination, cancellations,
  # notifications and both transports. What is here is the three things it cannot know — what this
  # server is called, which tools it has, and the two hooks that make a failure observable — plus
  # the wiring that keeps the behaviour layer where the suite already drives it.
  #
  # **The recording is no longer served.** `data/surface.json` used to be the bytes `initialize` and
  # `tools/list` answered with; it is now the oracle `mcp_tools_golden_test.rb` reconciles the SDK's
  # output against. A server that answers a recorded handshake is not implementing the protocol, it
  # is reproducing one answer to it, and every capability the SDK negotiates would be a lie the
  # recording does not tell.
  class Server
    # The protocol version the recording pins. It is the SDK's latest *handshake* version, so
    # naming it is a statement rather than a guess; a client that asks for an older version is
    # answered in the version it asked for, and one that asks for a modern (stateless) version is
    # counter-offered this one, which is what a legacy `initialize` can legitimately negotiate.
    PROTOCOL_VERSION = "2025-11-25"

    # Exactly what the recording advertises, and nothing more.
    #
    # The SDK's default capabilities claim `listChanged: true` on tools, prompts and resources and
    # add a `logging` capability. This server never changes a list (its surface is compiled in) and
    # does not implement `logging/setLevel`, so those defaults would be promises to a client that
    # the server cannot keep. The recording already told the truth here; the explicit hash keeps it.
    CAPABILITIES = {
      tools: { listChanged: false },
      prompts: { listChanged: false },
      resources: { listChanged: false, subscribe: false },
    }.freeze

    def initialize(tools:, client: nil)
      @tools = tools
      @client = client
    end

    # A server for one conversation. The stdio process builds one; the hosted endpoint builds one
    # per request, so the caller's credential is the one its tools write with and never outlives
    # the request that presented it.
    def mcp_server
      MCP::Server.new(
        name: Identity::NAME,
        title: Identity::TITLE,
        version: Identity::VERSION,
        description: Identity::DESCRIPTION,
        instructions: Identity::INSTRUCTIONS,
        tools: Surface::ALL,
        prompts: Prompts::ALL,
        resources: Resources::ALL,
        resource_templates: Resources::TEMPLATES,
        capabilities: CAPABILITIES,
        # Resources read documents that are not tool calls, so the client travels beside the tool
        # set. A per-request server (the hosted endpoint) builds both from the caller's credential.
        server_context: { tools: @tools, client: @client },
        configuration: configuration,
      )
    end

    def configuration
      MCP::Configuration.new(
        protocol_version: PROTOCOL_VERSION,
        # The handler is where a missing *value* is caught, with the service's own per-field 422.
        # Full schema validation here would pre-empt those refusals with a JSON-Schema message and
        # change what a model is told for a mistake the service can explain better. The one check
        # that still runs before the handler is the SDK's `required` check, whose sentence names the
        # missing fields — see `docs/known-limits.md`.
        validate_tool_call_arguments: false,
        # Our results always carry `structuredContent: {result: ...}`, which every declared output
        # schema requires, so holding ourselves to the schemas costs nothing and catches a tool that
        # stops answering in the shape it advertises.
        validate_tool_call_results: true,
        around_request: method(:record_request),
        exception_reporter: method(:report_exception),
      )
    end

    # Start the stdio transport. Its loop ends at EOF; an interrupt ends it with the status a
    # harness expects.
    def run
      MCP::Server::Transports::StdioTransport.new(mcp_server).open
    end

    private

    # One structured line per request, on stderr.
    #
    # stderr is not decoration: stdout is the protocol channel, and a log line written there is a
    # message the client would try to parse. The SDK calls this around every request, with the
    # instrumentation hash it mutates as it goes, so the tool name is read after the handler ran.
    def record_request(data)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      failure = nil
      begin
        yield
      rescue => e
        failure = e
        raise
      ensure
        log(
          "event" => "mcp_request",
          "method" => data[:method],
          "tool" => data[:tool_name],
          "error" => failure&.class&.name,
          "duration_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1),
        )
      end
    end

    # A crash is recorded where it can be found rather than only withheld from the model. The
    # sentence itself must not travel: the SDK withholds it for the reason CWE-209 names.
    def report_exception(exception, context = {})
      log(
        "event" => "mcp_exception",
        "error" => exception.class.name,
        "message" => exception.message.to_s[0, 500],
        "context" => context.is_a?(Hash) ? context.slice(:method, :request_id) : nil,
      )
    end

    def log(fields)
      return unless Config.log?

      $stderr.puts(JSON.generate(fields.compact))
      $stderr.flush
    rescue StandardError
      # Logging is not allowed to be the failure: a closed stderr during shutdown is not a
      # protocol error, and raising here would turn a clean EOF into a traceback.
      nil
    end
  end
end
