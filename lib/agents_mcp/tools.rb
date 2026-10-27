# frozen_string_literal: true

require_relative "client"
require_relative "rendering"

require_relative "tools/claims"
require_relative "tools/decisions"
require_relative "tools/profile"
require_relative "tools/rails"
require_relative "tools/releases"
require_relative "tools/reports"
require_relative "tools/search"
require_relative "tools/upgrade"

module AgentsMcp
  # The thirty-two tools' behaviour, in the domain modules beside this file.
  #
  # What lives here is the *behaviour* the schema cannot carry: the HTTP call, the sentence a
  # refusal carries, and the rendering of an answer. The names, descriptions, schemas and
  # annotations live in `surface.rb`, and the protocol lives in the SDK. The split is by the same
  # domains the tool surface is grouped by, and every method name is unchanged — `HANDLERS`
  # dispatches to them, and the 1,342-line behaviour suite calls them directly.
  class Tools
    # A field the tool cannot answer without, or a refusal naming it.
    #
    # These are reads of a service this process does not own, so a 200 whose body
    # lacks a key is a contract break between two deployments rather than a
    # caller's mistake — and it still has to reach the caller, because an uncaught
    # error arrives at the model with the text left on the server, which is the
    # failure `ToolError` exists to prevent. Optional fields are read with `[]` and
    # never come through here.
    def self.need(body, *keys)
      current = body
      keys.each do |key|
        unless current.is_a?(Hash) && current.key?(key)
          raise ToolError,
            "the service's response did not contain `#{keys.join('.')}`, which this " \
            "tool reads — it may be running a version that does not send it."
        end
        current = current[key]
      end
      current
    end

    def initialize(client)
      @client = client
    end

    # The HTTP client, which resources read documents through. It is a reader, not a second
    # way to make a tool call: the tools remain the whole behaviour surface.
    attr_reader :client

    # The name a `tools/call` arrives under to the method that answers it. It is
    # also the whole set of tools this build implements, which the golden test
    # reconciles against `surface.json` and `surface.rb`: a declared tool with no method
    # here would answer `Unknown tool`, and a method with no declaration would never be called.
    HANDLERS = {
      "check_lockfile_ruby_compatibility" => :check_lockfile_ruby_compatibility,
      "check_ruby_compatibility" => :check_ruby_compatibility,
      "check_upgrade" => :check_upgrade,
      "claim_report" => :claim_report,
      "find_answer" => :find_answer,
      "get_decision" => :get_decision,
      "list_decisions" => :list_decisions,
      "propose_decision" => :propose_decision,
      "create_decision" => :create_decision,
      "resolution_plan" => :resolution_plan,
      "withdraw_decision" => :withdraw_decision,
      "scan_upgrade_delta" => :scan_upgrade_delta,
      "get_project_profile" => :get_project_profile,
      "propose_profile" => :propose_profile,
      "find_rails_edits" => :find_rails_edits,
      "flag_report" => :flag_report,
      "gem_migrations" => :gem_migrations,
      "get_report" => :get_report,
      "list_upgrade_targets" => :list_upgrade_targets,
      "plan_gem_moves" => :plan_gem_moves,
      "precheck_report" => :precheck_report,
      "propose_resolution" => :propose_resolution,
      "rails_ladder" => :rails_ladder,
      "rails_upgrade_plan" => :rails_upgrade_plan,
      "record_outcome" => :record_outcome,
      "record_release_facts" => :record_release_facts,
      "release_report" => :release_report,
      "search_reports" => :search_reports,
      "submit_report" => :submit_report,
      "submit_reports" => :submit_reports,
      "triage_failures" => :triage_failures,
      "verify_report" => :verify_report,
    }.freeze

    def known?(name)
      HANDLERS.key?(name)
    end

    def call(name, args)
      raise ToolError, "Unknown tool: #{name}" unless HANDLERS.key?(name)

      send(HANDLERS[name], args)
    end

    include Claims
    include Decisions
    include Profile
    include RailsUpgrade
    include Releases
    include Reports
    include Search
    include Upgrade
  end
end
