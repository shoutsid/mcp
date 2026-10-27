# frozen_string_literal: true

require "mcp"

module AgentsMcp
  # The two conversions the SDK boundary needs, in one place.
  #
  # **A refusal written for the model must reach the model.** `lib/mcp/README.md` records
  # the trap this file exists to keep closed: an anticipated failure raised as anything the
  # transport does not understand reaches the model as `Error executing tool <name>`, with the
  # sentence left on the server. The SDK's own behaviour for a raised exception is to withhold the
  # message and answer a generic JSON-RPC error, so a `ToolError` is caught here and *returned* as
  # an `MCP::Tool::Response` with `error: true`. Every other exception is a crash and is left to
  # raise, so it reaches the SDK's `exception_reporter` and is recorded where it can be found.
  #
  # **Arguments arrive deeply symbolized.** The SDK's transports parse incoming JSON with
  # `JSON.parse(..., symbolize_names: true)`, so a tool sees symbol keys at every nesting level,
  # including inside arrays, and the behaviour layer reads strings throughout. `stringify` is the
  # one adapter; it is tested through the shape a transport actually delivers rather than through a
  # string-keyed in-process call, which is the difference the SDK's own documentation warns about.
  module Context
    # Answer one tool call, or turn its anticipated refusal into a result the model can act on.
    def self.respond(name, arguments, server_context)
      tools = server_context && server_context[:tools]
      raise "no tool set was supplied for #{name}" if tools.nil?

      text = tools.call(name, stringify(arguments)).to_s
      MCP::Tool::Response.new(
        [{ type: "text", text: text }],
        # The SDK mirrors a plain string here beside the text when a tool returns one; we state it
        # explicitly because the output schema every tool declares requires `result`, and Phase 5's
        # `validate_tool_call_results` holds us to it.
        structured_content: { "result" => text },
      )
    rescue ToolError => e
      # The prefix is the one the recorded error shape carries. What matters is the sentence after
      # it: the text is ours, written for a caller to act on, and it is delivered rather than
      # logged.
      MCP::Tool::Response.new(
        [{ type: "text", text: "Error executing tool #{name}: #{e.message}" }],
        error: true,
      )
    end

    # Symbol keys to string keys, at every level, without touching values.
    def self.stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
      when Array
        value.map { |item| stringify(item) }
      else
        value
      end
    end
  end
end
