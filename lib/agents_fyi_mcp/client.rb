# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "encoding"

module AgentsFyiMcp
  # A refusal the caller can act on, and nothing else.
  #
  # Every sentence raised here is written for a caller to act on — register a key, send `q`
  # not `query`, this reads forward moves — so it travels as this type and nothing else does.
  class ToolError < StandardError; end

  # The reply from the service, with the two shapes a caller needs: the status and
  # the parsed body. `headers` is a flat Hash of lowercased name to value, the way
  # Net::HTTP wants to hand them over once the arrays are joined.
  Response = Struct.new(:status, :headers, :body, keyword_init: true) do
    def json
      JSON.parse(body)
    end
  end

  # The one place an HTTP call is made, and the one place a failure is turned into a
  # sentence. An error written for a reader is not delivered by having been written:
  # anticipated failures are raised through here, as `ToolError`, or they are crashes.
  class Client
    # What a write with no credential is told, and it is transport-specific: the sentence has to
    # name the thing the *caller* can change.
    #
    # The stdio server reads `AGENTS_FYI_API_KEY` from its process, so naming the variable is
    # actionable. The hosted endpoint reads each request's own header and stores no key, so telling
    # a remote caller to set an environment variable names something it cannot reach — the one
    # direction an error must not fail in. `HttpApp` passes the hosted sentence; everything else
    # defaults to the stdio one.
    STDIO_CREDENTIAL_HINT =
      "AGENTS_FYI_API_KEY is not set, so this tool cannot authenticate. " \
      "Register an operator to obtain a key."
    HOSTED_CREDENTIAL_HINT =
      "no operator key was presented, so this tool cannot authenticate. " \
      "Send it as `X-API-Key: afy_…` (or `Authorization: Bearer afy_…`), or register " \
      "an operator to obtain a key."

    # Net::HTTP by default; a test substitutes a transport that records the request
    # and returns a queued `Response`, which is how the tool behaviours are checked
    # with no deployment behind them.
    def self.http_transport(timeout)
      lambda do |method, url, headers, body|
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        request = method == "GET" ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body if body
        response = http.request(request)
        Response.new(
          status: response.code.to_i,
          headers: response.each_header.to_h,
          body: response.body.to_s,
        )
      end
    end

    def initialize(base_url:, api_key: nil, timeout: 25, record: true, transport: nil,
      credential_hint: STDIO_CREDENTIAL_HINT)
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @api_key = (api_key || "").strip
      @timeout = timeout
      @record = record
      @credential_hint = credential_hint
      @transport = transport || Client.http_transport(timeout)
    end

    attr_reader :base_url

    def request(method, path, authenticated: false, params: nil, json: nil)
      perform(method, path, authenticated: authenticated, params: params, json: json).json
    end

    # A body that is not JSON, which is the one resource that is not the API: `llms.txt`.
    # The failure shaping is the same as `request`'s, so a resource read that could not be made
    # still carries the sentence a caller can act on rather than a parser error.
    def text(path)
      perform("GET", path, authenticated: false).body.to_s
    end

    # `record=false` when this server's reads must not be counted as demand. Empty
    # under the default, so an ordinary caller's request is unchanged: the search log
    # is the only signal the service has about what people cannot find, and a
    # synthetic row does not look wrong — it looks like a user.
    def demand_params
      @record ? {} : { "record" => "false" }
    end

    # The path for one report, with the id encoded rather than interpolated. An id of
    # `../operators/me` is not a 404, it is a different endpoint, and a `?` inside it
    # starts a query string; percent-encoding confines the value to the path segment
    # the caller meant to name, whatever it happens to contain.
    def self.report_path(report_id, suffix = "")
      "/api/reports/#{Encoding.quote(report_id, safe: '')}#{suffix}"
    end

    def report_path(report_id, suffix = "")
      Client.report_path(report_id, suffix)
    end

    private

    # One request, and the one place a failure is turned into a sentence.
    def perform(method, path, authenticated:, params: nil, json: nil)
      url = "#{@base_url}#{path}"
      query = params && !params.empty? ? Encoding.urlencode(params.to_a) : ""
      url = "#{url}?#{query}" unless query.empty?

      headers = request_headers(authenticated)
      body = json.nil? ? nil : JSON.generate(json)

      begin
        response = @transport.call(method, url, headers, body)
      rescue StandardError => e
        # Also anticipated: the tool can say what happened, and a model told the
        # service was unreachable retries or reports it, where one told "Error
        # executing tool" can only guess. Nothing below this line is a response,
        # so a transport that raises is unreachable whatever it raised.
        raise ToolError, "could not reach #{@base_url}: #{e}"
      end

      if response.status >= 400
        message = "#{response.status} from #{path}: #{error_message(response)}"
        hint = retry_hint(response)
        message = "#{message} — #{hint}" if hint
        raise ToolError, message
      end
      response
    end

    def request_headers(authenticated)
      headers = { "Accept" => "application/json" }
      return headers unless authenticated

      raise ToolError, @credential_hint if @api_key.empty?
      headers["X-API-Key"] = @api_key
      headers
    end

    def error_message(response)
      body = begin
        response.json
      rescue JSON::ParserError
        return response.body.to_s[0, 400]
      end
      error = body["error"]
      if error.is_a?(Hash)
        message = (error["message"] || error).to_s
        # The per-field list is the half a caller can act on: the message says the
        # request was refused and these say which field and why. Reading only the
        # message left a model told "Request validation failed." with no way to find
        # the field it had spelled wrong.
        fields = field_details(error["details"])
        return fields.empty? ? message : "#{message} (#{fields})"
      end
      (body["detail"] || body).to_s[0, 400]
    end

    # A 422's per-field failures as one clause, or empty when there are none. Shaped
    # for a model rather than a debugger: `field: message` pairs joined by a
    # semicolon, because the alternative is a repr of a list of dicts, which costs
    # context and reads like a crash.
    def field_details(details)
      return "" unless details.is_a?(Array)

      details.filter_map do |item|
        next unless item.is_a?(Hash) && item["message"]

        "#{item['field'] || 'field'}: #{item['message']}"
      end.join("; ")
    end

    # How long to wait before trying again, when the service said. Only a 429 gets
    # this sentence: the skill tells a model to honour `Retry-After`, and until the
    # value was surfaced the instruction was unactionable.
    def retry_hint(response)
      return nil unless response.status == 429

      wait = response.headers.fetch("retry-after", "").to_s.strip
      return "retry after #{wait}s" if wait.match?(/\A\d+\z/) && wait.to_i.positive?

      "rate limited: wait for the window to reset before retrying"
    end
  end
end
