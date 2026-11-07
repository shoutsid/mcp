# frozen_string_literal: true

require "json"
require "mcp"
require "yaml"

module AgentsMcp
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

    # The skills this component ships, as files and as resources.
    #
    # **The tools are grouped by the job a caller has, not by the domain they live in.** One
    # skill for all thirty-eight tools is a document a model has to read whole before it can
    # reach one; four skills are four documents, and a harness loads the one that matches the
    # work. The grouping is declared here once, and the index and the resources are generated
    # from it so a skill cannot be listed without being readable.
    #
    # **The description is read from the file's own frontmatter.** The skill's `description` is
    # the sentence a harness uses to decide whether to load it, which is exactly what a
    # resource's description is for — so the file is the source of truth and there is no second
    # copy to drift. The canonical files live in the service's `.claude/skills/`; the copies
    # here are held byte-identical by the service's contract suite, because the image's build
    # context is this component and the repository root is not in it.
    module Skills
      NAMES = %w[agents agents-upgrade agents-rails agents-decisions].freeze
      ROOT = File.join(COMPONENT_ROOT, "data", "skills")

      def self.each
        NAMES.map { |name| load(name) }
      end

      def self.load(name)
        path = File.join(ROOT, name, "SKILL.md")
        { name: name, description: frontmatter(File.read(path))["description"].to_s, path: path }
      end

      # The index a client reads before it knows which skill it wants: one row per skill, the
      # same sentence the harness sees, and the URI to read the whole thing at.
      def self.index
        lines = [
          "# Agents skills",
          "",
          "The MCP server's tools, grouped by the job you have. Each skill is self-contained;",
          "read the one that matches, or the whole text at its own URI.",
          "",
          "| Skill | Load it when |",
          "|---|---|",
        ]
        NAMES.each { |name| lines << row(load(name)) }
        lines << ""
        lines << "Read one with `agents://skills/<name>`."
        lines.join("\n")
      end

      # One index row: the skill's name and the sentence a harness chooses it by.
      def self.row(skill)
        "| `#{skill[:name]}` | #{skill[:description]} |"
      end

      # The `name` and `description` between the leading `---` fences. A skill without them is a
      # file a harness cannot choose, so an empty hash is a fact worth failing on rather than a
      # default to paper over.
      def self.frontmatter(text)
        match = text.match(/\A---\n(.*?)\n---\n/m)
        return {} unless match

        YAML.safe_load(match[1]) || {}
      end
    end

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
      uri "agents://discovery"
      resource_name "discovery"
      title "The service's discovery document"
      description "`/.well-known/agents.json`: every route, enum, idempotency header and trace " \
                  "language the service declares, fetched live."
      mime_type "application/json"

      def self.contents(server_context:)
        Resources.fetched(uri, server_context, "/.well-known/agents.json",
          mime_type: mime_type, json: true)
      end
    end

    # The plain-language document an agent is pointed at before it has a tool list.
    class Llms < MCP::Resource
      uri "agents://llms.txt"
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
      uri "agents://readme"
      resource_name "readme"
      title "The MCP server's README"
      description "The tool table, the annotation rules and the transport's contract."
      mime_type "text/markdown"

      def self.contents(server_context:)
        Resources.file(uri, File.join(COMPONENT_ROOT, "README.md"), mime_type: mime_type)
      end
    end

    # The index of the skills: which one to load for the job you have. It is generated from
    # `Skills`, so a skill cannot be added to the list without also being readable.
    class SkillsIndex < MCP::Resource
      uri "agents://skills"
      resource_name "skills"
      title "The agents skills"
      description "The tools grouped by job: which skill to load for the work you have, and " \
                  "the URI to read each one at."
      mime_type "text/markdown"

      def self.contents(server_context:)
        Resources.text(uri, Skills.index, mime_type: mime_type)
      end
    end

    # One skill, as a resource. The four differ only in which file they read, so the base reads
    # the registry and each subclass names its skill; the title, description and URI all come
    # from that one name.
    class SkillResource < MCP::Resource
      def self.skill(name)
        data = Skills.load(name)
        uri "agents://skills/#{name}"
        resource_name "skill_#{name.tr('-', '_')}"
        title "The #{name} skill"
        description data[:description]
        mime_type "text/markdown"
        @skill_name = name
      end

      def self.skill_name
        @skill_name
      end

      def self.contents(server_context:)
        Resources.file(uri, Skills.load(skill_name)[:path], mime_type: mime_type)
      end
    end

    class SkillAgents < SkillResource
      skill "agents"
    end

    class SkillAgentsUpgrade < SkillResource
      skill "agents-upgrade"
    end

    class SkillAgentsRails < SkillResource
      skill "agents-rails"
    end

    class SkillAgentsDecisions < SkillResource
      skill "agents-decisions"
    end

    ALL = [Discovery, Llms, Readme, SkillsIndex, SkillAgents, SkillAgentsUpgrade, SkillAgentsRails,
      SkillAgentsDecisions].freeze

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
