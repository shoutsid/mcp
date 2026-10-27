# frozen_string_literal: true

require "mcp"
require "rack"

require_relative "../agents_fyi_mcp"

module AgentsFyiMcp
  # The hosted MCP endpoint: one SDK server per request, on the Streamable HTTP transport.
  #
  # **A server per request is what gives each caller their own credential.** Reads need no key; a
  # write uses the key the caller presented, and the server holds it only for the length of the
  # request. There is no session, no key store and nothing that outlives the request that sent the
  # key — a shared server would have to keep the last caller's credential somewhere, which is the
  # one thing this endpoint must not do.
  #
  # **It is a service of its own rather than a Rails route.** `lib/mcp` is a client: a route
  # would make it a package, pull `json_schemer` into the container that answers the internet, and
  # put the MCP surface on the application's boot path. ADR 0003 and the client boundary decide it.
  #
  # **The transport's hardening is configured here, once.** `allowed_hosts` is the public hostname
  # (the SDK's DNS-rebinding protection allows loopback by default and nothing else), `allowed_origins`
  # is empty because no browser is meant to call this, and `max_request_bytes` is a hard bound rather
  # than the SDK's 4 MiB default. `serve_subscriptions_listen: false` is stated even though sessions
  # are off, so the values are chosen rather than inherited.
  class HttpApp
    # `transport` is the test seam, for the reason `Tools`' transport is one: the credential rule
    # and the transport's hardening are decisions this file makes, and checking them must not
    # require a deployment. It is the *transport* rather than the client so that the production
    # client — and the credential hint it carries — is what a test exercises; production passes
    # nothing and gets Net::HTTP. `client_factory` is a narrower seam for the one test that has to
    # observe how a client was built, and it defaults to the production path.
    def initialize(hosts: Config.mcp_hosts, origins: Config.mcp_origins, max_request_bytes: Config.max_request_bytes,
      transport: nil, client_factory: nil)
      @hosts = hosts
      @origins = origins
      @max_request_bytes = max_request_bytes
      @transport = transport
      @client_factory = client_factory || method(:build_client)
    end

    def call(env)
      client = @client_factory.call(credential(env))
      server = Server.new(tools: Tools.new(client), client: client).mcp_server
      transport(server).call(env)
    end

    private

    def build_client(key)
      Client.new(
        base_url: Config.base_url,
        api_key: key,
        timeout: Config.timeout,
        record: Config.record?,
        # The refusal names the header this caller can set, not the environment variable the stdio
        # server reads. Both are the same rule; only the actionable half differs.
        credential_hint: Client::HOSTED_CREDENTIAL_HINT,
        transport: @transport,
      )
    end

    def transport(server)
      MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        allowed_hosts: @hosts,
        allowed_origins: @origins,
        max_request_bytes: @max_request_bytes,
        serve_subscriptions_listen: false,
      )
    end

    # `X-API-Key: afy_…` or `Authorization: Bearer afy_…`, read per request.
    #
    # The bearer form exists because an MCP client that speaks OAuth-shaped configuration has a
    # place to put a token and none to put a header; both are the same operator key and neither is
    # stored. An empty credential is anonymous, which is a working configuration for every read and
    # is refused by the write tools with their own sentence.
    def credential(env)
      header = env["HTTP_X_API_KEY"].to_s.strip
      return header unless header.empty?

      match = env["HTTP_AUTHORIZATION"].to_s.match(/\ABearer\s+(\S+)\s*\z/i)
      match ? match[1] : ""
    end
  end
end
