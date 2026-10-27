# frozen_string_literal: true

require_relative "test_helper"

# **The profile and delta tools, over the recorded transport.** A tool that changes a profile is a
# proposal and says so; a tool that scans a delta names what moved rather than re-reporting the
# whole tree.
class McpProfileToolsTest < McpTest
  BANNER = AgentsFyiMcp::Rendering::UNTRUSTED_BANNER

  def test_the_delta_tool_sends_the_manifest_and_renders_the_classification
    api.respond(
      "from_version" => "7.0.0", "to_version" => "7.1.0",
      "edits" => [], "manual" => [],
      "counts" => { "automatic" => 0, "manual" => 0, "files" => 1, "lines" => 3 },
      "files_read" => 1, "lines_read" => 3, "truncated" => false, "stored" => false,
      "next_step" => "Nothing moved since the manifest you sent.",
      "delta" => { "added" => ["app/models/user.rb"], "changed" => [],
                   "unchanged" => ["app/models/post.rb"], "deleted" => [],
                   "unlisted" => [], "scanned" => ["app/models/user.rb"], "skipped" => 1 }
    )

    out = api.tools.scan_upgrade_delta(
      "from_version" => "7.0.0", "to_version" => "7.1.0",
      "files" => "### app/models/user.rb\nclass User\nend\n",
      "known" => [{ "path" => "app/models/post.rb", "sha256" => "a" * 64, "size" => 10 }],
      "deleted" => "app/models/old.rb"
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/rails/scan/delta")
    assert_equal ["app/models/user.rb"],
      call.json["files"].map { |file| file["path"] }
    assert_equal [{ "path" => "app/models/post.rb", "sha256" => "a" * 64, "size" => 10 }],
      call.json["known"]
    assert_equal ["app/models/old.rb"], call.json["deleted"]
    assert_includes out, "delta: 1 added, 0 changed, 1 unchanged, 0 deleted, 1 skipped"
    assert_includes out, "stored: no"
    assert out.start_with?(BANNER)
  end

  def test_a_delta_with_nothing_to_read_is_refused_before_the_network
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.scan_upgrade_delta(
        "from_version" => "7.0.0", "to_version" => "7.1.0", "files" => "", "deleted" => ""
      )
    end

    assert_match(/nothing would be read/, error.message)
    assert_empty api.calls
  end

  def test_the_profile_read_names_the_fields_and_the_problem
    api.respond(
      "project_id" => "p1", "name" => "Lighthouse", "slug" => "lighthouse",
      "repo_url" => "https://github.com/example/lighthouse",
      "from_version" => "7.0.0", "to_version" => "7.1.0",
      "profile" => { "suite" => { "kind" => "rspec", "command" => "bundle exec rspec" } },
      "problem" => "cheks.0 has no command",
      "agent_policy" => { "policy" => "propose", "capabilities" => ["answer"] },
      "proposals" => { "proposed" => 2, "accepted" => 1, "rejected" => 0 },
      "next_step" => "POST the fields a person should review."
    )

    out = api.tools.get_project_profile("project_id" => "p1")

    assert api.calls[0].path.end_with?("/api/upgrades/projects/p1/profile")
    assert_includes out, "Lighthouse (lighthouse)"
    assert_includes out, "the profile is not walkable: cheks.0 has no command"
    assert_includes out, "\"kind\":\"rspec\""
    assert_includes out, "2 open, 1 accepted"
    assert_includes out, "consultant policy: propose"
  end

  def test_a_profile_proposal_says_it_applies_nothing
    api.respond(
      "id" => "proposal-1", "project_id" => "p1", "state" => "proposed",
      "fields" => { "suite" => { "value" => { "kind" => "minitest" } } }
    )

    out = api.tools.propose_profile(
      "project_id" => "p1",
      "fields" => { "suite" => { "value" => { "kind" => "minitest", "command" => "bin/rails test" },
                                 "source" => "Gemfile.lock" } },
      "evidence" => { "suite" => { "path" => "Gemfile.lock", "line" => 1 } },
      "provenance" => { "model" => "test/model" }
    )

    call = api.calls[0]
    assert call.path.end_with?("/api/upgrades/projects/p1/profile_proposals")
    assert_equal "bin/rails test", call.json.dig("fields", "suite", "value", "command")
    assert_includes out, "proposal-1"
    assert_includes out, "applies nothing"
  end
end
