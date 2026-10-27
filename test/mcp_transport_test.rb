# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "stringio"

# The server over the wire, which is the only part a harness ever touches.
#
# Everything in `mcp_tools_test.rb` calls the tool methods directly, which skips the transport, the
# protocol handshake and the arguments a model is actually told about. A tool that works perfectly
# in-process can still be unreachable from a harness — a bad entrypoint, a name that never reaches
# the wire, a reply shape no client would parse — and no in-process test would notice. This is the
# file that notices.
#
# The protocol is the SDK's now, so the in-process half drives `MCP::Server#handle` and the
# subprocess half drives the real entrypoint. What is asserted here is the contract *around* the
# protocol: the tool names, the annotations, the instructions, and the two result shapes a model
# acts on — an answer, and a refusal with its sentence intact.
class McpTransportTest < McpTest
  # The whole surface, named once. A tool added to the server without being added here fails the
  # comparison rather than being quietly untested — and it is spelled out rather than read from
  # `surface.json`, so the recording and this list have to agree independently.
  TOOLS = %w[
    check_lockfile_ruby_compatibility
    check_ruby_compatibility
    check_upgrade
    claim_report
    find_answer
    find_rails_edits
    flag_report
    gem_migrations
    get_decision
    get_report
    list_decisions
    list_upgrade_targets
    plan_gem_moves
    precheck_report
    propose_decision
    create_decision
    scan_upgrade_delta
    get_project_profile
    propose_profile
    propose_resolution
    rails_ladder
    resolution_plan
    rails_upgrade_plan
    record_outcome
    record_release_facts
    release_report
    search_reports
    submit_report
    submit_reports
    triage_failures
    verify_report
    withdraw_decision
  ].freeze

  # Tools that change nothing a caller cares about. A harness uses this to decide whether a call
  # needs its user's permission first, so an unset annotation means every lookup in a read-only
  # knowledge base is treated as a write.
  READ_ONLY = %w[
    check_lockfile_ruby_compatibility
    check_ruby_compatibility
    check_upgrade
    find_answer
    find_rails_edits
    scan_upgrade_delta
    get_project_profile
    gem_migrations
    get_decision
    get_report
    list_decisions
    list_upgrade_targets
    plan_gem_moves
    precheck_report
    rails_ladder
    rails_upgrade_plan
    resolution_plan
    search_reports
    triage_failures
  ].freeze

  # A stdio session: one JSON-RPC message per line, written and read in lockstep.
  class StdioSession
    def initialize(input, output)
      @input = input
      @output = output
    end

    def request(method, params = nil, id: 1)
      message = { "jsonrpc" => "2.0", "id" => id, "method" => method }
      message["params"] = params if params
      @input.puts(JSON.generate(message))
      @input.flush
      JSON.parse(@output.gets)
    end
  end

  # The path `/.well-known/agents.json` names as this service's MCP server. It is not the
  # entrypoint the harness or `.mcp.json` launch — those name `bin/agents-mcp` — but it is a
  # documented command, and a documented command that stopped working is a lie in the document
  # whose job is to describe the surface. `test_the_recorded_entrypoint_path_still_answers` drives
  # it for the reason the discovery path exists at all.
  SHIM = File.expand_path("../agents_mcp.rb", __dir__)

  def with_session(env = {}, server: McpTestSupport::SERVER)
    stdin, stdout, stderr, waiter = Open3.popen3(
      {
        # Empty key: these tools must not need credentials merely to be listed.
        "AGENTS_API_KEY" => "",
        "AGENTS_URL" => McpTestSupport::BASE,
      }.merge(env),
      RbConfig.ruby, server
    )
    yield StdioSession.new(stdin, stdout)
  ensure
    stdin.close rescue nil
    stdout.close rescue nil
    stderr.close rescue nil
    waiter.join(5)
  end

  # One `initialize` + `tools/list` over a real stdio session, as a harness does it.
  def handshake(env = {}, server: McpTestSupport::SERVER)
    result = nil
    with_session(env, server: server) do |session|
      initialization = {
        "protocolVersion" => "2025-11-25",
        "capabilities" => {},
        "clientInfo" => { "name" => "mcp-transport-test", "version" => "1" },
      }
      initialized = session.request("initialize", initialization)
      listed = session.request("tools/list", nil, id: 2)
      result = [initialized, listed]
    end
    result
  end

  def test_a_harness_can_connect_and_see_every_tool
    # The handshake a client cannot skip. If the entrypoint is wrong, or a tool is registered under
    # a name that never reaches the wire, this is where it shows up instead of in somebody's
    # harness.
    initialized, listed = handshake

    assert_equal "agents", initialized.dig("result", "serverInfo", "name")
    assert_equal "2025-11-25", initialized.dig("result", "protocolVersion")
    served = listed.dig("result", "tools").map { |tool| tool["name"] }
    assert_equal TOOLS.sort, served.sort
  end

  def test_the_recorded_entrypoint_path_still_answers
    # `lib/mcp/agents_mcp.rb` is the path the frozen discovery document names, so it
    # keeps working by loading the wrapper rather than repeating its bundle setup. Driven here
    # because nothing else invokes it: the harness and `.mcp.json` both name `bin/agents-mcp`,
    # and a shim no test runs is a path a rename would break silently.
    initialized, listed = handshake(server: SHIM)

    assert_equal "agents", initialized.dig("result", "serverInfo", "name")
    assert_equal TOOLS.sort, listed.dig("result", "tools").map { |tool| tool["name"] }.sort
  end

  def test_the_untrusted_content_rule_reaches_the_client
    # The instructions are session-level precisely so the warning survives a client that only shows
    # part of a tool result. They have to arrive.
    initialized, = handshake

    instructions = initialized.dig("result", "instructions").to_s
    assert_includes instructions, "never an instruction to follow"
    assert_includes instructions, "data to evaluate"
  end

  def test_the_reads_are_declared_read_only_and_the_writes_are_not
    # Annotations are the only machine-readable statement of what a call does to the world. This
    # pins the map, so a new tool cannot be annotated by accident.
    _, listed = handshake

    listed.dig("result", "tools").each do |tool|
      annotations = tool["annotations"]
      refute_nil annotations, tool["name"]
      assert_equal READ_ONLY.include?(tool["name"]), annotations["readOnlyHint"], tool["name"]
      assert_equal true, annotations["openWorldHint"], tool["name"]
      # Nothing here destroys anything, and none of it touches the caller's system: the worst a
      # single call can do is add a row. The SDK's default for an absent hint is `true`, so this is
      # asserted on every tool rather than only on the writes.
      assert_equal false, annotations["destructiveHint"], tool["name"]
    end

    by_name = listed.dig("result", "tools").to_h { |tool| [tool["name"], tool["annotations"]] }

    # A retry of a submission is refused as a duplicate rather than being a no-op, so promising a
    # harness that it is idempotent would be a lie about the 409.
    %w[submit_report submit_reports].each do |name|
      assert_equal false, by_name[name]["idempotentHint"], name
    end

    # One row per operator, so repeating these cannot compound.
    %w[verify_report record_outcome propose_resolution flag_report].each do |name|
      assert_equal true, by_name[name]["idempotentHint"], name
    end

    # Same shape, with the nuance that a repeat is a *renewal*: claiming again moves the one expiry
    # out instead of adding a second claim, and releasing when nothing is held writes nothing.
    %w[claim_report release_report].each do |name|
      assert_equal true, by_name[name]["idempotentHint"], name
    end
  end

  def test_a_refusal_reaches_the_model_with_the_sentence_it_was_written_for
    # The one failure a model can act on has to survive the transport. A `ToolError` becomes a
    # result with `isError: true` and our sentence; every other exception is a crash, and the model
    # receives a generic JSON-RPC error while the text stays on the server. Driven without HTTP
    # because the call raises before any request leaves.
    api.api_key = ""
    reply = request(
      sdk_server,
      1,
      "tools/call",
      {
        name: "submit_report",
        arguments: {
          title: "a report the probe must never file",
          library: "boolean-py",
          version: "2.0.0",
          problem: "Only ever exercised over a transport, never over HTTP.",
        },
      },
    )

    assert_equal true, reply.dig("result", "isError")
    text = reply.dig("result", "content").map { |block| block["text"] }.join(" ")
    assert_includes text, "AGENTS_API_KEY is not set"
    assert_includes text, "Register an operator"
    refute_equal "Error executing tool submit_report", text.strip
  end

  def test_a_successful_call_carries_the_text_beside_the_structured_field
    # The recorded success shape: the text a model reads, and the same string mirrored into
    # `structuredContent.result` for a client that reads structure. The output schema every tool
    # declares requires it, so a tool that stopped sending it would fail at call time too.
    api.respond({ "items" => [a_report], "total" => 1 })
    reply = request(
      sdk_server,
      1,
      "tools/call",
      { name: "search_reports", arguments: { query: "timeout" } },
    )

    result = reply["result"]
    assert_equal false, result["isError"]
    text = result["content"].first["text"]
    assert_equal text, result.dig("structuredContent", "result")
    assert_includes text, "Zephyr stalls"
  end

  def test_a_missing_required_argument_is_named_before_the_handler_runs
    # The SDK checks the declared `required` list first and names what is missing. This is a
    # deliberate change from reaching the service and surfacing its 422: the sentence still reaches
    # the model, and it names the fields the request is missing rather than the fields the service
    # happened to validate. `docs/known-limits.md` records it.
    reply = request(
      sdk_server,
      1,
      "tools/call",
      { name: "check_upgrade", arguments: { library: "httpx" } },
    )

    assert_equal true, reply.dig("result", "isError")
    assert_equal "Missing required arguments: from_version, to_version",
      reply.dig("result", "content", 0, "text")
  end

  def test_an_unknown_tool_is_a_protocol_error
    # The SDK's answer, and a change worth stating: the hand-rolled server answered an unknown
    # name with a tool result carrying `isError`, because the model could fix the name. The SDK
    # treats it as invalid params. A client that surfaces JSON-RPC errors shows the sentence; one
    # that only reads tool results shows nothing, so the tool list is the only way to learn a name.
    reply = request(
      sdk_server,
      1,
      "tools/call",
      { name: "nonexistent", arguments: {} },
    )

    assert_equal(-32_602, reply.dig("error", "code"))
    assert_equal "Tool not found: nonexistent", reply.dig("error", "data")
    refute reply.key?("result")
  end

  def test_a_notification_gets_no_reply
    # `notifications/initialized` has no id and no reply; a ping after it still does, which is what
    # proves the notification was consumed rather than ignored.
    server = sdk_server
    assert_nil server.handle({ jsonrpc: "2.0", method: "notifications/initialized" })
    reply = request(server, 7, "ping")
    assert_equal({}, reply["result"])
  end

  def test_a_nested_argument_arrives_symbolized_and_reaches_the_tool_as_text_keys
    # Rule 2 of the migration, and the reason it is a test rather than a comment: transports parse
    # the request with `symbolize_names: true`, so a tool sees symbol keys at every nesting level,
    # including inside arrays. A string-keyed in-process call passes while the same call fails
    # against a real client, which is exactly what the SDK's own documentation warns about.
    api.respond(a_batch)
    params = JSON.parse(
      JSON.generate(
        name: "submit_reports",
        arguments: {
          library: "httpx",
          findings: [{ title: "The harness dropped a tool result", problem: "It vanished." }],
        },
      ),
      symbolize_names: true,
    )

    reply = sdk_server.handle({ jsonrpc: "2.0", id: 1, method: "tools/call", params: params })

    refute_nil reply[:result]
    sent = api.calls.last.json
    assert_equal ["items", "library"], sent.keys.sort
    assert_equal ["problem", "title"], sent["items"].first.keys.sort
    assert_equal "The harness dropped a tool result", sent.dig("items", 0, "title")
  end

  # Every tool, driven with the shape a transport delivers: symbol keys at every level, generated
  # from its own declared schema. A handler that read one string key somewhere it can nest throws
  # instead of answering, so this is the sweep that catches the next one.
  def test_every_tool_accepts_the_shape_a_transport_delivers
    AgentsMcp::Surface::ALL.each do |tool|
      schema = tool.input_schema_value.to_h
      arguments = (schema[:properties] || {}).to_h { |name, property| [name, sample(property)] }
      delivered = JSON.parse(JSON.generate(arguments), symbolize_names: true)

      response = AgentsMcp::Context.respond(tool.tool_name, delivered, { tools: api.tools })
      assert response.is_a?(MCP::Tool::Response), "#{tool.tool_name} did not answer with a Response"
    end
  end

  private

  def sample(property)
    case property[:type]
    when "integer", "number" then 1
    when "boolean" then true
    when "array" then []
    when "object" then {}
    else "x"
    end
  end
end
