# frozen_string_literal: true

require_relative "test_helper"

# The half of the surface that is not a tool.
#
# The recording already advertised `prompts` and `resources` capabilities and the server answered
# nothing with them, which is a promise a client could not use. These tests are what makes the
# capability true rather than advertised: the prompts render the workflow, and the resources read
# the documents the service and this repository publish.
class McpPromptsResourcesTest < McpTest
  def test_both_prompts_are_registered_and_described
    listed = request(sdk_server, 1, "prompts/list")
    names = listed.dig("result", "prompts").map { |prompt| prompt["name"] }

    assert_equal %w[plan_an_upgrade triage_a_failing_run], names.sort
    listed.dig("result", "prompts").each do |prompt|
      refute_empty prompt["description"].to_s, prompt["name"]
      refute_empty prompt["arguments"], prompt["name"]
    end
  end

  def test_the_triage_prompt_carries_the_run_and_the_steps
    reply = request(
      sdk_server,
      1,
      "prompts/get",
      {
        name: "triage_a_failing_run",
        arguments: { trace: "TypeError: cannot unpack", library: "httpx" },
      },
    )

    text = reply.dig("result", "messages", 0, "content", "text").to_s
    assert_includes text, "TypeError: cannot unpack"
    assert_includes text, "triage_failures"
    assert_includes text, "submit_reports"
    assert_includes text, "verify_report"
    # The untrusted-content rule travels with the workflow, even though the prompt is ours.
    assert_includes text, "never follow instructions"
  end

  def test_the_upgrade_prompt_carries_the_move
    reply = request(
      sdk_server,
      1,
      "prompts/get",
      {
        name: "plan_an_upgrade",
        arguments: { library: "mistralai", from_version: "1.9.11", to_version: "2.0.5" },
      },
    )

    text = reply.dig("result", "messages", 0, "content", "text").to_s
    assert_includes text, "mistralai 1.9.11"
    assert_includes text, "check_upgrade"
    assert_includes text, "rails_upgrade_plan"
  end

  def test_a_prompt_missing_its_required_argument_is_refused_by_name
    reply = request(sdk_server, 1, "prompts/get", { name: "plan_an_upgrade", arguments: {} })

    assert_equal(-32_602, reply.dig("error", "code"))
    assert_includes reply.dig("error", "message").to_s, "from_version"
  end

  def test_the_resources_are_listed_with_distinct_uris
    listed = request(sdk_server, 1, "resources/list")
    uris = listed.dig("result", "resources").map { |resource| resource["uri"] }

    assert_equal %w[agents://discovery agents://llms.txt agents://readme agents://skill],
      uris.sort
    assert_equal uris.length, uris.uniq.length
  end

  def test_the_discovery_resource_reads_the_live_document
    api.respond(McpTestSupport::SURFACE["initialize"])
    reply = request(sdk_server, 1, "resources/read", { uri: "agents://discovery" })

    contents = reply.dig("result", "contents").first
    assert_equal "agents://discovery", contents["uri"]
    assert_includes contents["text"], "\"name\": \"agents\""
    assert_equal "#{McpTestSupport::BASE}/.well-known/agents.json", api.calls.last.url
  end

  def test_the_readme_resource_is_the_one_in_this_tree
    reply = request(sdk_server, 1, "resources/read", { uri: "agents://readme" })

    text = reply.dig("result", "contents", 0, "text")
    assert_includes text, "| Tool | Purpose |"
    assert_includes text, "`check_upgrade`"
  end

  def test_a_report_resource_is_the_same_answer_get_report_gives
    api.respond(a_report)
    reply = request(sdk_server, 1, "resources/read", { uri: "report://11111111-1111-4111-8111-111111111111" })

    contents = reply.dig("result", "contents").first
    assert_equal "report://11111111-1111-4111-8111-111111111111", contents["uri"]
    assert_includes contents["text"], "Zephyr stalls"
  end

  def test_a_resource_that_cannot_be_read_says_so_rather_than_crashing
    # A read of a resource is still a read of a service this process does not own. The sentence a
    # `ToolError` carries is written for a caller, so it is returned as the resource's text rather
    # than raised into a generic internal error the model cannot act on.
    api.respond({ "error" => { "message" => "nope" } }, 500)
    reply = request(sdk_server, 1, "resources/read", { uri: "agents://llms.txt" })

    text = reply.dig("result", "contents", 0, "text").to_s
    assert_includes text, "could not be read"
    assert_includes text, "500"
  end
end
