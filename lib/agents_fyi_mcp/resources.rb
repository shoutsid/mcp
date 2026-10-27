# frozen_string_literal: true

require "json"
require "mcp"

module AgentsFyiMcp
  # The documents behind the tools, and one live report, as resources a client can read.
  #
  # The recording already advertised a `resources` capability and answered nothing with it. These
  # make it mean something without adding a second source of truth: the discovery document and
  # `llms.txt` are fetched from the service at read time, and the README and skill are the files
  # this component ships, so a client reads what the repository publishes rather than a copy that
  # could drift.
  #
  # Every one is read-only, and none is required to use the server — the tools remain the whole
  # surface for a client that does not implement resources.
  module Resources
    COMPONENT_ROOT = File.expand_path("../..", __dir__)

    # A read that cannot be made is a fact about the resource, not about the protocol: the sentence
    # a `ToolError` carries is written for a caller to act on, so it is returned as the resource's
    # text rather than raised into a generic internal error.
    def self.client(server_context)
      client = server_context && server_context[:client]
      raise "no service client was supplied for this resource" if client.nil?

      client
    end

    def self.text(uri, text, mime_type: "text/plain")
      MCP::Resource::TextContents.new(uri: uri, mime_type: mime_type, text: text)
    end

    def self.fetched(uri, server_context, path, mime_type:, json: false)
      client = client(server_context)
      body = json ? JSON.pretty_generate(client.request("GET", path)) : client.text(path)
      text(uri, body, mime_type: mime_type)
    rescue ToolError => e
      text(uri, "#{path} could not be read: #{e.message}", mime_type: "text/plain")
    end

    def self.file(uri, path, mime_type: "text/plain")
      return text(uri, File.read(path), mime_type: mime_type) if File.exist?(path)

      text(uri, "#{File.basename(path)} is not present in this deployment.", mime_type: "text/plain")
    end

    # The machine-readable surface of the service the tools call.
    class Discovery < MCP::Resource
      uri "agents-fyi://discovery"
      resource_name "discovery"
      title "The service's discovery document"
      description "`/.well-known/agents-fyi.json`: every route, enum, idempotency header and trace " \
                  "language the service declares, fetched live."
      mime_type "application/json"

      def self.contents(server_context:)
        Resources.fetched(uri, server_context, "/.well-known/agents-fyi.json",
          mime_type: mime_type, json: true)
      end
    end

    # The plain-language document an agent is pointed at before it has a tool list.
    class Llms < MCP::Resource
      uri "agents-fyi://llms.txt"
      resource_name "llms_txt"
      title "llms.txt"
      description "The service's own introduction for a language model, fetched live."
      mime_type "text/plain"

      def self.contents(server_context:)
        Resources.fetched(uri, server_context, "/llms.txt", mime_type: mime_type)
      end
    end

    # The tool reference, from the component that ships it.
    class Readme < MCP::Resource
      uri "agents-fyi://readme"
      resource_name "readme"
      title "The MCP server's README"
      description "The tool table, the annotation rules and the transport's contract."
      mime_type "text/markdown"

      def self.contents(server_context:)
        Resources.file(uri, File.join(COMPONENT_ROOT, "README.md"), mime_type: mime_type)
      end
    end

    # The skill, which is the README explained as *when* to reach for a tool. It ships as
    # `data/SKILL.md`, a copy of `.claude/skills/agents-fyi/SKILL.md` held in step by a test,
    # because the image's build context is this component and the repository root is not in it.
    class Skill < MCP::Resource
      uri "agents-fyi://skill"
      resource_name "skill"
      title "The agents-fyi skill"
      description "When to reach for each tool, and the rules for report text that is not yours."
      mime_type "text/markdown"

      def self.contents(server_context:)
        Resources.file(uri, File.join(COMPONENT_ROOT, "data/SKILL.md"), mime_type: mime_type)
      end
    end

    ALL = [Discovery, Llms, Readme, Skill].freeze

    # One report, by id: the same answer `get_report` gives, without a tool call.
    class Report < MCP::ResourceTemplate
      uri_template "report://{id}"
      resource_template_name "report"
      title "One report"
      description "A report's whole body and every fix proposed for it, by report id."
      mime_type "text/plain"

      def self.contents(id:, server_context:)
        tools = server_context && server_context[:tools]
        raise "no tool set was supplied for this resource" if tools.nil?

        Resources.text("report://#{id}", tools.call("get_report", { "report_id" => id }))
      rescue ToolError => e
        Resources.text("report://#{id}", "report #{id} could not be read: #{e.message}")
      end
    end

    TEMPLATES = [Report].freeze
  end
end
