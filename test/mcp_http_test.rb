# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/agents_fyi_mcp/http_app"
require "rack/mock"
require "rack/mock_request"

# The hosted endpoint, driven as a Rack application.
#
# Phase 6's decision is that the endpoint is a *service of its own*, so this file checks the three
# things that are code rather than deployment: the handshake and tool list travel over the
# Streamable HTTP transport, the caller's credential is read per request and stored nowhere, and the
# SDK's DNS-rebinding and request-size limits are configured here rather than inherited. What it
# cannot prove is the socket and the built image — CI's `mcp-image` job is that half.
class McpHttpTest < McpTest
  # The default app goes through the production client — the credential hint and all — with only
  # the HTTP transport swapped, so a test cannot pass against a client the endpoint does not build.
  # `client_factory` is used by the one test that must see how a client was constructed.
  def app(transport: api.method(:transport), client_factory: nil)
    AgentsFyiMcp::HttpApp.new(
      hosts: %w[agents.shoutsid.fyi],
      origins: [],
      max_request_bytes: 64 * 1024,
      transport: transport,
      client_factory: client_factory,
    )
  end

  def post(request, message, headers = {})
    request.post(
      "/",
      input: JSON.generate(message),
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => "127.0.0.1:8080",
      **headers,
    )
  end

  def initialize_message
    { jsonrpc: "2.0", id: 1, method: "initialize", params: initialize_params }
  end

  def test_the_endpoint_serves_the_handshake_and_the_tool_list
    request = Rack::MockRequest.new(app)

    initialized = post(request, initialize_message)
    assert_equal 200, initialized.status
    body = JSON.parse(initialized.body)
    assert_equal "agents-fyi", body.dig("result", "serverInfo", "name")
    assert_equal "2025-11-25", body.dig("result", "protocolVersion")

    listed = post(request, { jsonrpc: "2.0", id: 2, method: "tools/list" })
    assert_equal 200, listed.status
    names = JSON.parse(listed.body).dig("result", "tools").map { |tool| tool["name"] }
    assert_equal McpTestSupport::SURFACE["tools"].map { |tool| tool["name"] }.sort, names.sort
  end

  def test_the_caller_s_key_is_read_per_request_and_never_stored
    # The factory is the observation point: an `initialize`/`tools/list` makes no service call, so
    # the only place the presented credential is visible is the client the endpoint builds for that
    # request. Each entry is what one request carried, in order.
    keys = []
    factory = lambda do |key|
      keys << key
      AgentsFyiMcp::Client.new(base_url: McpTestSupport::BASE, api_key: key, transport: api.method(:transport))
    end
    request = Rack::MockRequest.new(app(client_factory: factory))

    post(request, initialize_message, "HTTP_X_API_KEY" => "afy_from_header")
    post(request, { jsonrpc: "2.0", id: 2, method: "tools/list" },
      "HTTP_AUTHORIZATION" => "Bearer afy_from_bearer")
    post(request, { jsonrpc: "2.0", id: 3, method: "tools/list" })

    # One client per request, each carrying only the credential that request presented. The third
    # request is anonymous, which is a working configuration for every read.
    assert_equal ["afy_from_header", "afy_from_bearer", ""], keys
  end

  def test_a_write_without_a_key_names_the_header_this_caller_can_set
    # The credential is absent rather than wrong, and the tool is the thing that says so. The
    # sentence is the stdio server's rule with the hosted half swapped: a remote caller cannot set
    # `AGENTS_FYI_API_KEY`, so a refusal naming it would send them to change something they do not
    # have — the one direction an error must not fail in. The stdio server's own wording is asserted
    # in `mcp_transport_test.rb`, where the variable *is* the actionable thing.
    request = Rack::MockRequest.new(app)
    reply = post(
      request,
      {
        jsonrpc: "2.0", id: 1, method: "tools/call",
        params: { name: "submit_report", arguments: { title: "t", library: "httpx", version: "1", problem: "p" } }
      },
    )

    body = JSON.parse(reply.body)
    assert_equal true, body.dig("result", "isError")
    text = body.dig("result", "content", 0, "text").to_s
    assert_includes text, "X-API-Key"
    assert_includes text, "register an operator"
    refute_includes text, "AGENTS_FYI_API_KEY"
  end

  def test_an_origin_the_endpoint_did_not_allow_is_refused
    # The SDK's DNS-rebinding protection: a browser cross-origin request is rejected unless the
    # origin is same-origin or allow-listed. The endpoint names no origins, because no browser is
    # meant to call it.
    request = Rack::MockRequest.new(app)
    reply = post(request, initialize_message, "HTTP_ORIGIN" => "https://evil.example")

    refute_equal 200, reply.status
  end

  def test_a_request_over_the_bound_is_refused
    request = Rack::MockRequest.new(app)
    reply = request.post(
      "/",
      input: "x" * (64 * 1024 + 1),
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => "127.0.0.1:8080",
    )

    refute_equal 200, reply.status
  end
end
