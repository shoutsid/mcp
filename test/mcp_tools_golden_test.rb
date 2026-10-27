# frozen_string_literal: true

require_relative "test_helper"

# The frozen MCP contract, reconciled against the surface the SDK now serves.
#
# **`data/surface.json` is an oracle, not the bytes a caller receives.** It recorded the handshake
# the server answered with before the SDK owned the protocol. The server now builds its surface from
# `surface.rb`, and this file holds the two together: every declared tool has a handler and a class,
# the SDK's `initialize` and `tools/list` still say what the recording says after the differences in
# § The allowed differences are applied, and the two documents that table the tools name all thirty-two.
#
# **The reconciliation is deliberately not equality.** Three differences are real and each is
# stated below; everything else has to match, which is what makes a transcription slip in a
# description fail here rather than in somebody's harness.
class McpToolsGoldenTest < McpTest
  # **The allowed differences, and why each is one.**
  #
  # 1. `$schema` on every input and output schema. The SDK emits
  #    `https://json-schema.org/draft/2020-12/schema`, the dialect MCP 2025-11-25 mandates, and the
  #    recording predates the SDK's emission of it. It is a statement of the dialect the schemas
  #    were always in, not a change to what a model is offered.
  # 2. `destructiveHint` on the read tools. The recording omits the field; the MCP default for an
  #    omitted `destructiveHint` is `true`, so omitting it was the one annotation this repository's
  #    README argued against. `surface.rb` states `false`, because nothing here destroys anything.
  #    The normalized comparison treats an absent hint in the recording as `false` for that reason,
  #    and only the read-only tools may use it: a write that omitted the hint would still be a lie.
  # 3. Nothing else. Field order is not a difference (JSON objects are unordered), and neither is
  #    the SDK adding a key it was not given — it adds none beyond the two above.
  def test_the_sdk_serves_the_recorded_surface
    initialized, listed = served

    assert_equal McpTestSupport::SURFACE["initialize"]["protocolVersion"], initialized["protocolVersion"]
    assert_equal McpTestSupport::SURFACE["initialize"]["capabilities"], initialized["capabilities"]
    assert_equal McpTestSupport::SURFACE["initialize"]["serverInfo"], initialized["serverInfo"]
    assert_equal McpTestSupport::SURFACE["initialize"]["instructions"], initialized["instructions"]

    recorded = McpTestSupport::SURFACE["tools"]
    assert_equal recorded.map { |tool| tool["name"] }, listed["tools"].map { |tool| tool["name"] },
      "the tools/list order is the recording's order"

    recorded.zip(listed["tools"]).each do |expected, actual|
      assert_equal normalize(expected), normalize(actual), "#{expected['name']} is not the recorded tool"
    end

    # The hint is stated rather than omitted, on every tool: the SDK's default for an absent
    # `destructiveHint` is `true`, so "nothing here destroys anything" has to be said.
    listed["tools"].each do |tool|
      assert tool.fetch("annotations").key?("destructiveHint"), tool["name"]
      assert_equal false, tool.dig("annotations", "destructiveHint"), tool["name"]
    end
  end

  def test_every_declared_tool_has_a_handler_and_a_surface_class
    declared = McpTestSupport::SURFACE["tools"].map { |tool| tool["name"] }
    handled = AgentsFyiMcp::Tools::HANDLERS.keys
    surfaced = AgentsFyiMcp::Surface::ALL.map(&:tool_name)

    assert_equal declared.sort, handled.sort
    assert_equal declared.sort, surfaced.sort
    assert_equal declared.length, declared.uniq.length, "a tool is declared twice"
  end

  def test_every_tool_carries_a_title_a_description_and_both_schemas
    # The description is the whole basis on which a model picks a tool, and the schemas are what it
    # fills in and reads back. A missing one is a tool a model cannot use, and it is invisible from
    # the handler that works perfectly.
    AgentsFyiMcp::Surface::ALL.each do |tool|
      name = tool.tool_name
      refute_nil tool.title_value, name
      refute_empty tool.description_value.to_s, name
      assert tool.description_value.length > 60, "#{name}: description too short to choose a tool by"

      schema = tool.input_schema_value.to_h
      assert_equal "object", schema[:type], name
      assert schema[:properties].is_a?(Hash), "#{name}: no input properties"

      output = tool.output_schema_value.to_h
      assert_equal "object", output[:type], name
      assert output[:properties].is_a?(Hash), "#{name}: no output properties"

      # Every tool's structured answer is `{result: <text>}`, which is the output schema the SDK is
      # asked to validate. A tool that declares one shape and returns another fails at call time.
      assert_equal ["result"], output[:required], name
    end
  end

  def test_the_skill_documents_every_tool_the_server_registers
    # The skill is the layer that says *when* to reach for a tool, and nothing tied it to the code
    # until now — it was one tool behind the moment a tool shipped, which is exactly the kind of rot
    # invisible from inside the repository's tests.
    assert_documents_every_tool(
      File.join(McpTestSupport::ROOT, "data/SKILL.md"), "skill"
    )
  end

  def test_the_readme_documents_every_tool_the_server_registers
    # The same guard one file over: `check_upgrade` shipped with a row in the skill and none in the
    # tool table and nothing failed, so both surfaces that table the tools are read here rather than
    # only the one that had a test.
    assert_documents_every_tool(File.join(McpTestSupport::ROOT, "README.md"), "README")
  end

  private

  def served
    @served ||= begin
      server = sdk_server
      initialized = request(server, 1, "initialize", initialize_params)
      listed = request(server, 2, "tools/list")
      [initialized.fetch("result"), listed.fetch("result")]
    end
  end

  # § The allowed differences are applied to both sides, and only those.
  def normalize(tool)
    copy = JSON.parse(JSON.generate(tool))
    copy["inputSchema"].delete("$schema")
    copy["outputSchema"].delete("$schema")

    annotations = copy["annotations"]
    if annotations && !annotations.key?("destructiveHint")
      raise "#{copy['name']} is a write with no destructiveHint" if annotations["readOnlyHint"] != true

      annotations["destructiveHint"] = false
    end
    copy
  end

  def assert_documents_every_tool(path, what)
    text = File.read(path)
    tools = McpTestSupport::SURFACE["tools"].map { |tool| tool["name"] }
    documented = tools.select { |name| text.include?("| `#{name}` |") }

    assert_equal tools.sort, documented.sort, "not in the #{what}'s tool table: #{(tools - documented).sort}"
  end
end
