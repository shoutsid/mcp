# frozen_string_literal: true

module AgentsFyiMcp
  class Tools
    # The upgrade tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module Upgrade
      def check_upgrade(args)
        params = {
          "library" => args["library"],
          "from_version" => args["from_version"],
          "to_version" => args["to_version"],
        }
        params["symbols"] = args["symbols"] if args["symbols"]
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]

        body = @client.request("GET", "/api/reports/upgrade", params: params)
        lines = [
          "#{self.class.need(body, 'library')} #{self.class.need(body, 'from_version')} " \
          "-> #{self.class.need(body, 'to_version')}",
          "reports examined: #{self.class.need(body, 'scanned')}",
        ]
        if body["truncated"]
          lines << "this library holds more reports than one check reads — the lists are partial"
        end

        changes = self.class.need(body, "changes")
        lines << "no recorded change crosses this move." if changes.empty?
        changes.each do |change|
          when_ = "broke in #{change['broken_in']}"
          when_ += ", still worked in #{change['from_version']}" if change["from_version"]
          marks = ""
          if change["affects_your_code"] == true
            marks = "  <-- yours"
          elsif change["affects_your_code"] == false
            far = Rendering.far_end(change, args["symbols"])
            marks =
              if far
                "  (this change is where your `#{far}` came from, not what broke it)"
              else
                "  (not a name you asked about)"
              end
          end
          lines << ""
          named = change["subject"] || "a name it does not record"
          lines << "- #{change['change_kind']}: #{named}"
          lines << "  #{when_} | #{change['status']} | " \
                   "trust #{Rendering.py(change['trust'])}#{marks}"
          lines << "  report_id #{change['report_id']} | #{change['title']}"
        end

        self.class.need(body, "unclassified").each do |one|
          lines << ""
          lines << "- not recorded as a change (#{one['reason']}): #{one['title']}"
          lines << "  at #{one['version']} | report_id #{one['report_id']}"
        end

        if body["unknown_symbols"]
          lines << ""
          lines << "no recorded change for this library names: " \
                   "#{body['unknown_symbols'].join(', ')} — that is unrecorded, not safe."
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      def list_upgrade_targets(args)
        params = { "limit" => args.fetch("limit", 25), "offset" => args.fetch("offset", 0) }
        status = args["status"]
        params["status"] = status if status && !status.empty?

        body = @client.request("GET", "/api/upgrades/targets", authenticated: true, params: params)
        count = self.class.need(body, "count")
        limit_max = self.class.need(body, "limit_max")
        targets = self.class.need(body, "targets")

        lines = ["#{count} repository(ies) in the upgrade queue"]
        lines << "one page carries at most #{limit_max}; page with `offset`" if count > limit_max
        lines << "nothing queued in this view" if targets.empty?

        targets.each do |target|
          lines << ""
          ref = target["ref"] ? "@#{target['ref']}" : ""
          lines << "- #{target['repo_url']}#{ref}"
          facts = []
          facts << "Rails #{target['rails_version']}" if target["rails_version"]
          facts << "needs Ruby #{target['ruby_floor']}" if target["ruby_floor"]
          facts << "status #{target['status']}"
          facts << "#{target['attempts']} attempt(s)" if target["attempts"]
          facts << "last tried #{target['last_attempt_at']}" if target["last_attempt_at"]
          lines << "  #{facts.join(' | ')}"
          lines << "  note: #{target['notes']}" if target["notes"]
          (target["reasons"] || []).each { |reason| lines << "  - #{reason}" }
        end

        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end
    end
  end
end
