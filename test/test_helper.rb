# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "rbconfig"
require "uri"

# The server logs one JSON line per protocol request, which is right for a deployment and noise
# beside a test runner's output. Nothing here asserts on the log, so the suite is the one place
# that turns it off.
ENV["AGENTS_FYI_MCP_LOG"] ||= "0"

require_relative "../lib/agents_fyi_mcp"

# Shared ground for the MCP suite: the frozen surface, a recorded HTTP transport so
# the tool behaviours are checked with no deployment behind them, and the report
# bodies the tests read.
#
# The empty key is the point of most of these: a read must work without a credential
# and a write must refuse before it reaches the network, and an `Api` that always had
# a key would never show either.
module McpTestSupport
  SURFACE = JSON.parse(File.read(File.expand_path("../data/surface.json", __dir__)))

  # The client repository's root: `lib/mcp` in the service checkout, or the checkout itself when
  # this repository is vendored as a submodule. The service-wide agreements are not here — they
  # live in the service's `test/contracts/mcp/` — so a path below this root is the client's own.
  ROOT = File.expand_path("..", __dir__)
  SERVER = File.expand_path("../bin/agents-fyi-mcp", __dir__)
  BASE = "http://service.test"

  # The URL is what actually leaves the process — query string and all — so the tests assert
  # on what a deployment would receive rather than on an argument dict this side built.
  class Api
    Call = Struct.new(:method, :url, :headers, :body, keyword_init: true) do
      def params
        query = url.include?("?") ? url.split("?", 2)[1] : ""
        URI.decode_www_form(query).to_h
      end

      # The path alone: a GET's arguments ride the query string, so a test that means
      # "this request reached that route" has to name the part before the `?`, or a
      # `?query=...` makes every such assertion false.
      def path
        url.split("?", 2).first
      end

      def json
        body && JSON.parse(body)
      end
    end

    attr_reader :calls
    attr_accessor :api_key, :record

    def initialize(api_key: "test-key", record: true)
      @api_key = api_key
      @record = record
      @calls = []
      @queued = [{}, 200, {}]
    end

    # The response the next request is answered with. A fresh `Tools` is built per
    # call, so a test can change `api_key`/`record` between calls and see it.
    def respond(payload, status = 200, headers = {})
      @queued = [payload, status, headers]
    end

    def clear!
      @calls.clear
    end

    def client
      AgentsFyiMcp::Client.new(
        base_url: BASE, api_key: @api_key, record: @record, transport: method(:transport)
      )
    end

    def tools
      AgentsFyiMcp::Tools.new(client)
    end

    def transport(method, url, headers, body)
      @calls << Call.new(method: method, url: url, headers: headers, body: body)
      payload, status, extra = @queued
      AgentsFyiMcp::Response.new(
        status: status,
        headers: extra.to_h { |name, value| [name.to_s.downcase, value] },
        body: JSON.generate(payload)
      )
    end
  end

  # A reply from `/api/reports/answer` that names no report, so nothing past the header is
  # read. Shared because several tests only need *an* answer body.
  def an_unknown_answer
    {
      "query" => "timeout", "verdict" => "unknown", "confidence" => "none",
      "answer" => nil, "reasons" => [], "caveats" => [], "dissent" => [],
      "alternatives" => [], "signatures" => [], "candidates_considered" => 0,
      "relaxed" => false,
      "next_step" => "Nothing recorded. If you solve it, submit the report."
    }
  end

  def a_report(**overrides)
    {
      "id" => "11111111-1111-4111-8111-111111111111",
      "title" => "Zephyr stalls when the handshake never completes",
      "library" => "httpx", "version" => "0.28.0",
      "problem" => "The handshake never completes and the stream stalls.",
      "resolution" => "Raise the read timeout.",
      "attempted" => nil, "environment" => nil,
      "status" => "resolved_verified",
      "submitted_by" => "22222222-2222-4222-8222-222222222222",
      "score" => 0.8, "trust" => 0.7, "match_type" => "both",
      "signatures" => ["typeerror", "stream()"], "truncated" => false
    }.merge(overrides.transform_keys(&:to_s))
  end

  # One-item triage reply, with the fields it hands back for submitting.
  def a_triage(kind: "package")
    {
      "items" => [
        {
          "index" => 0, "verdict" => "new", "action" => "submit",
          "advice" => "Nothing close in this library.",
          "title" => "The harness dropped a tool result",
          "library" => "httpx", "version" => "0.28.0", "subject_kind" => kind,
          "signatures" => ["typeerror"], "candidate" => nil,
          "candidate_count" => 0, "notes" => []
        }
      ],
      "summary" => {
        "items" => 1, "new" => 1, "duplicates" => 0, "similar" => 0,
        "known_share" => 0.0, "advice" => "All 1 worth submitting."
      }
    }
  end

  def a_batch
    {
      "items" => [
        {
          "index" => 0, "status" => "created",
          "report_id" => "44444444-4444-4444-8444-444444444444",
          "title" => "The harness dropped a tool result", "detail" => nil, "notes" => []
        }
      ],
      "summary" => {
        "items" => 1, "created" => 1, "duplicates" => 0, "rejected" => 0,
        "advice" => "All 1 filed."
      }
    }
  end

  # A reply from `/api/reports/upgrade` with the shape a caller acts on.
  def an_upgrade_body(**overrides)
    {
      "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5",
      "changes" => [
        {
          "report_id" => "99999999-9999-4999-8999-999999999999",
          "title" => "mistralai 2.0.5 removed mistralai.ArchiveFTModelOut",
          "subject" => "ArchiveFTModelOut", "change_kind" => "symbol_removed",
          "from_version" => "1.9.11", "broken_in" => "2.0.5",
          "status" => "resolved_verified", "trust" => 0.9,
          "resolution" => "`ArchiveFTModelOut` is gone in mistralai 2.0.5.",
          "replacement" => nil, "affects_your_code" => true
        }
      ],
      "unclassified" => [], "scanned" => 60, "truncated" => false,
      "asked_symbols" => ["archiveftmodelout"], "unknown_symbols" => [],
      "unmatched_changes" => 0,
      "next_step" => "1 of the 1 change(s) crossing this move is about a name you asked about."
    }.merge(overrides.transform_keys(&:to_s))
  end

  # A plan whose two halves differ in size on purpose: the documented digest and the
  # executed record are two different kinds of statement, and the rendering has to
  # keep them apart.
  def a_rails_plan_body(**overrides)
    {
      "from_version" => "3.2.22", "to_version" => "5.1.0",
      "steps" => [
        {
          "from_version" => "3.2.0", "to_version" => "4.0.0", "name" => "Rails 4.0",
          "requires_ruby" => "1.9.3",
          "guidance" => "Change the Rails version to 4.0.0 in the Gemfile.",
          "note" => "The largest of the steps.",
          "changes" => [
            {
              "subject" => "attr_accessible", "kind" => "removed",
              "replacement" => "params.require(:user).permit(:name)",
              "removed_in" => nil, "automatic" => false, "findable" => true,
              "enforced_in_your_move" => true,
              "note" => "Both attr_accessible and attr_protected are gone.",
              "source" => "3.2 → 4.0, Active Record"
            },
            {
              "subject" => "config.i18n.enforce_available_locales",
              "kind" => "default_changed", "replacement" => nil, "removed_in" => nil,
              "automatic" => false, "findable" => false, "enforced_in_your_move" => false,
              "note" => "The default is now true.",
              "source" => "4.0 → 4.1, I18n enforcing available locales"
            }
          ],
          "observed" => [], "observed_unclassified" => 3,
          "counts" => { "documented" => 2, "automatic" => 0, "enforced" => 1, "observed" => 0 }
        },
        {
          "from_version" => "5.0.0", "to_version" => "5.1.0", "name" => "Rails 5.1",
          "requires_ruby" => "2.2.2",
          "guidance" => "Change the Rails version to 5.1.0 in the Gemfile.", "note" => "",
          "changes" => [
            {
              "subject" => "before_filter", "kind" => "renamed",
              "replacement" => "before_action", "removed_in" => "5.1.0",
              "automatic" => true, "findable" => true, "enforced_in_your_move" => true,
              "note" => "Gone in 5.1.",
              "source" => "5.0, controller filters (deprecated; removed in 5.1)"
            }
          ],
          "observed" => [
            {
              "report_id" => "11111111-1111-4111-8111-111111111111",
              "title" => "actionpack 5.1.0 removed ActionController::Live::Buffer",
              "subject" => "Live::Buffer", "change_kind" => "symbol_removed",
              "replacement" => nil, "from_version" => "5.0.7", "broken_in" => "5.1.0",
              "status" => "resolved_verified", "trust" => 0.8,
              "resolution" => "Use ActionController::Live directly.",
              "affects_your_code" => nil
            }
          ],
          "observed_unclassified" => 0,
          "counts" => { "documented" => 1, "automatic" => 1, "enforced" => 1, "observed" => 1 }
        }
      ],
      "documented" => 3, "observed" => 1, "unplaced" => 2, "truncated" => false,
      "components" => ["rails", "railties", "actionpack"],
      "guide" => "https://guides.rubyonrails.org/upgrading_ruby_on_rails.html",
      "stored" => false,
      "next_step" => "2 step(s) from 3.2.0 to 5.1.0, one minor release at a time: " \
                     "3 documented change(s) to work through, 2 of which raise by the " \
                     "release you named."
    }.merge(overrides.transform_keys(&:to_s))
  end
end

class McpTest < Minitest::Test
  include McpTestSupport

  def api
    @api ||= Api.new
  end

  # The SDK server this component builds, with a stubbed service behind it. Driven through
  # `handle` rather than the transport where a test is about the protocol's answer rather than the
  # socket; `mcp_transport_test.rb` is the half that opens a real stdio session.
  def sdk_server(tools: nil, client: nil)
    AgentsFyiMcp::Server.new(tools: tools || api.tools, client: client || api.client).mcp_server
  end

  # One request through the SDK, parsed the way a transport parses it and answered the way a
  # client receives it: symbol keys in, string keys out after a JSON round trip.
  def request(server, id, method, params = nil)
    message = { jsonrpc: "2.0", id: id, method: method }
    message[:params] = params if params
    reply = server.handle(message)
    reply && JSON.parse(JSON.generate(reply))
  end

  # The `initialize` every real client sends. The SDK validates it, and a handshake without a
  # `clientInfo` is refused with `Missing or invalid clientInfo` rather than answered.
  def initialize_params(version: "2025-11-25")
    { protocolVersion: version, capabilities: {}, clientInfo: { name: "mcp-test", version: "1" } }
  end
end
