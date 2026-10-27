# frozen_string_literal: true

require "json"

module AgentsMcp
  class Tools
    # **The decision tools: what a walk stopped on, and what an agent may say about it.**
    #
    # An agent can read a question, read the plan it belongs to, propose an effect with its
    # provenance, and withdraw its own proposal. It cannot accept one: `Decision::Answers` refuses a
    # service key, and there is deliberately no tool that would make the operator's act a formality.
    # Every write here calls the same operator route the site admin and the walker call, so a
    # proposal made from a harness is the row a person reviews rather than a second kind of answer.
    module Decisions
      def list_decisions(args)
        params = {}
        %w[state block_kind project change_key].each do |field|
          value = args[field]
          params[field] = value if value && !value.to_s.empty?
        end
        params["limit"] = args["limit"] if args["limit"]

        body = @client.request("GET", "/api/upgrades/decisions", authenticated: true,
          params: params)
        questions = self.class.need(body, "decisions")
        limit = self.class.need(body, "limit")
        count = self.class.need(body, "count")

        lines = ["#{count} decision(s), showing at most #{limit}"]
        lines << "none matches this view" if questions.empty?
        questions.each do |question|
          lines << ""
          lines << "- #{question['id']} | #{question['state']} | " \
                   "#{question['block_kind'] || 'question'} | #{question['project']}"
          rung = [question["rung_from"], question["rung_to"]].compact.join(" -> ")
          lines << "  rung: #{rung}" unless rung.empty?
          lines << "  subject: #{question['subject']}" if question["subject"]
          lines << "  #{first_line(question['question'])}"
          lines << "  target is blocked; answer or dismiss it before the walk can continue" if
            question["blocked"]
          lines << "  change_key: #{question['change_key']}" if question["change_key"]
        end
        lines.join("\n")
      end

      def get_decision(args)
        body = @client.request("GET", decision_path(args["id"]), authenticated: true)
        lines = [
          "decision: #{self.class.need(body, 'id')}",
          "state: #{self.class.need(body, 'state')}",
          "block_kind: #{body['block_kind'] || 'question'}",
          "project: #{self.class.need(body, 'project')}",
        ]
        rung = [body["rung_from"], body["rung_to"]].compact.join(" -> ")
        lines << "rung: #{rung}" unless rung.empty?
        lines << "change_key: #{body['change_key']}" if body["change_key"]
        lines << "subject: #{body['subject']}" if body["subject"]
        lines << "question: #{body['question']}"
        lines << "target: #{body.dig('target', 'status')}" if body["target"]
        append_pairs(lines, "context", body["context"])
        append_pairs(lines, "evidence", body["evidence"])

        options = Array(body["options"])
        if options.empty?
          lines << "options: none recorded"
        else
          lines << "options:"
          options.each do |option|
            label = option["label"].to_s.empty? ? "option #{option['index']}" : option["label"]
            lines << "  #{option['index']}. #{label}#{option['key'] ? " [#{option['key']}]" : ''}"
            lines << "     #{option['detail']}" if option["detail"]
            Array(option["effects"]).each { |effect| lines << "     effect: #{effect_line(effect)}" }
          end
        end

        accepted = body["accepted"]
        if accepted
          lines << "accepted: #{accepted['choice']} (#{accepted['effect_kind'] || 'answer'})"
          lines << "  proposed_by: #{accepted['proposed_by']}"
          lines << "  accepted_by: #{accepted['accepted_by']}"
          lines << "  verified_by_run_id: #{accepted['verified_by_run_id']}" if
            accepted["verified_by_run_id"]
          Array(accepted["effects"]).each { |effect| lines << "  effect: #{effect_line(effect)}" }
        else
          lines << "accepted: none — an account administrator must accept an option or proposal"
        end

        proposals = Array(body["answers"]).reject { |answer| answer["accepted"] || answer["withdrawn_at"] }
        unless proposals.empty?
          lines << "proposals (none is applied until a person accepts one):"
          proposals.each do |answer|
            lines << "  - answer_id #{answer['id']} | #{answer['choice']} | " \
                     "by #{answer['proposed_by']}"
            lines << "    effect: #{effect_line(answer['effects'].first)}" if
              Array(answer["effects"]).any?
          end
        end
        lines << "attempts: #{body['attempts']}" if body.key?("attempts")
        lines.join("\n")
      end

      def propose_decision(args)
        stance = args["stance"].to_s
        stance = "answer" if stance.empty?
        payload = {
          "choice" => args["choice"],
          "stance" => stance,
          "effects" => effects_of(args["effects"]),
          "needs" => args["needs"].is_a?(Array) ? args["needs"] : [],
          "rationale" => args["rationale"].to_s,
          "provenance" => args["provenance"].is_a?(Hash) ? args["provenance"] : {}
        }
        payload["option_key"] = args["option_key"] if args["option_key"]
        payload["proposed_by"] = args["proposed_by"] || "model:agents-mcp"

        body = @client.request("POST", "#{decision_path(args['id'])}/answers",
          authenticated: true, json: payload)
        answer_id = self.class.need(body, "proposed_answer")
        verb = stance == "answer" ? "Proposed answer" : "Recorded a #{stance} stance on"
        "#{verb} decision #{self.class.need(body, 'id')} as #{answer_id}. Nothing is applied: " \
          "an account administrator accepts an answer in the site admin or the project's portal."
      end

      # **An advisory note is a question, not an effect.** An agent that finds something the walk
      # did not ask about may record it for a person; it does not get to apply it, and an advisory
      # row never blocks a target.
      def create_decision(args)
        payload = {
          "project" => args["project"],
          "project_id" => args["project_id"],
          "subject" => args["subject"],
          "question" => args["question"],
          "block_kind" => args["block_kind"].to_s.empty? ? "scan_manual" : args["block_kind"],
          "rung_to" => args["rung_to"].to_s.empty? ? "unknown" : args["rung_to"],
          "change_key" => args["change_key"],
          "context" => args["context"].is_a?(Hash) ? args["context"] : {},
          "evidence" => args["evidence"].is_a?(Hash) ? args["evidence"] : {},
          "source" => "agent",
          "advisory" => true
        }.reject { |_key, value| value.nil? || value.to_s.empty? }
        payload["rung_from"] = args["rung_from"] if args["rung_from"]

        body = @client.request("POST", "/api/upgrades/decisions", authenticated: true,
          json: payload)
        "Recorded advisory decision #{self.class.need(body, 'id')} for #{body['project']}. It " \
          "does not block the walk; a person may answer it or dismiss it."
      end

      def withdraw_decision(args)
        path = "#{decision_path(args['id'])}/answers/" \
               "#{Encoding.quote(args['answer_id'], safe: '')}/withdraw"
        body = @client.request("POST", path, authenticated: true, json: {})
        "Withdrew answer #{self.class.need(body, 'withdrawn_answer')} from decision " \
          "#{self.class.need(body, 'id')}. The question is open for another proposal."
      end

      def resolution_plan(args)
        params = {}
        params["from"] = args["from"] if args["from"] && !args["from"].to_s.empty?
        params["to"] = args["to"] if args["to"] && !args["to"].to_s.empty?
        path = "/api/upgrades/projects/#{Encoding.quote(args['project_id'], safe: '')}/resolution"
        body = @client.request("GET", path, authenticated: true, params: params)

        lines = [
          "project: #{self.class.need(body, 'project')}",
          "move: #{body['from_version']} -> #{body['to_version']}",
        ]
        changes = self.class.need(body, "changes")
        lines << "no change is known for this move" if changes.empty?
        changes.each do |change|
          lines << ""
          lines << "- #{change['change_key']} | authority: #{change['authority'] || 'none'}"
          if change["in_force"]
            lines << "  answer: #{change['in_force']['answer']}" if change["in_force"]["answer"]
            lines << "  question: #{first_line(change['in_force']['question'])}" if
              change["in_force"]["question"]
          end
          Array(change["reports"]).each do |report|
            lines << "  report_id #{report['id']} | #{report['status']} | #{report['title']}"
          end
          Array(change["open_questions"]).each do |question|
            lines << "  open question #{question['id']}: #{first_line(question['question'])}"
          end
        end
        missing = Array(body["missing"])
        lines << "" << "missing: #{missing.join(', ')}" if missing.any?
        lines << "A report is evidence, not an applied edit; only a person accepts a question."
        lines.join("\n")
      end

      private

      def decision_path(id)
        "/api/upgrades/decisions/#{Encoding.quote(id, safe: '')}"
      end

      def effects_of(value)
        return value if value.is_a?(Array)
        return [] if value.nil? || value.to_s.empty?

        parsed = JSON.parse(value.to_s)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        raise ToolError, "`effects` must be a JSON list of effects, e.g. " \
                         "`[{\"kind\": \"patch\", \"payload\": {...}}]`."
      end

      def append_pairs(lines, label, value)
        return unless value.is_a?(Hash) && value.any?

        lines << "#{label}:"
        value.each do |key, item|
          lines << "  #{key}: #{item.is_a?(Array) ? item.join(', ') : item}"
        end
      end

      def effect_line(effect)
        return "none" unless effect.is_a?(Hash)

        payload = effect["payload"].is_a?(Hash) ? effect["payload"] : {}
        detail = payload["path"] || payload["name"] || payload["change_key"] ||
          payload["key"] || ""
        window = effect["applies_when"].is_a?(Hash) && effect["applies_when"].any? ?
          " (#{effect['applies_when'].map { |key, value| "#{key} #{value}" }.join(', ')})" : ""
        "#{effect['kind']} #{detail}#{window}".strip
      end

      def first_line(text)
        text.to_s.lines.first.to_s.strip
      end
    end
  end
end
