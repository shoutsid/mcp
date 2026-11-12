# frozen_string_literal: true

module AgentsMcp
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
          # **The exact range, when the corpus has one.** `introduced_in` is the release a
          # bisection established; its absence is a window rather than a release, and the basis
          # says which of the two the caller is reading.
          basis = change.dig("affected_versions", "basis")
          exact = change.dig("affected_versions", "introduced_in")
          when_ += ", introduced in #{exact}" if exact
          when_ += " (#{basis})" if basis && basis != "observed_endpoints"
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
        # **The negative space, and the documented half.** A `changes` list with nothing in it means
        # "no report crosses this move"; it does not mean the move was examined, and the two used to
        # be indistinguishable. `examined`/`clean` are the executions the corpus holds, and
        # `documented` is a reading of the release's own words — kept apart, because one is evidence
        # and the other is not.
        examined = Array(body["examined"])
        clean = Array(body["clean"])
        if examined.empty?
          lines << ""
          lines << "no examination of this move is recorded — an absence of evidence, not a pass."
        else
          lines << ""
          lines << "#{examined.length} examined cell(s) of this move; #{clean.length} came back clean."
          examined.first(5).each do |cell|
            lines << "  - #{cell['check_kind']}: #{cell['outcome']} (#{cell['environment_digest']})"
          end
        end
        documented = Array(body["documented"])
        unless documented.empty?
          lines << ""
          lines << "#{documented.length} documented change(s) from the release's own notes " \
                   "(readings, not executions):"
          documented.first(5).each do |change|
            named = change["subject"] || "a change it does not name"
            lines << "  - #{change['kind']} at #{change['version']}: #{named}"
          end
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **What the corpus has actually examined, as opposed to what it has reported broken.**
      #
      # `check_upgrade` answers from reports; this answers from examinations, and the distinction is
      # the whole point of the object: a move with no report and a clean cell is examined and clean,
      # a move with no report and no cell is unexamined, and the two used to be the same empty list.
      def check_compatibility(args)
        params = {
          "library" => args["library"],
          "from_version" => args["from_version"],
          "to_version" => args["to_version"],
        }
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        body = @client.request("GET", "/api/reports/upgrade", params: params)

        lines = [
          "#{self.class.need(body, 'library')} #{self.class.need(body, 'from_version')} " \
          "-> #{self.class.need(body, 'to_version')}",
        ]
        examined = self.class.need(body, "examined")
        clean = self.class.need(body, "clean")
        if examined.empty?
          lines << "no examination of this move is recorded — an absence of evidence, not a pass"
        else
          lines << "#{examined.length} examined cell(s) of this move; #{clean.length} came back clean"
          examined.each do |cell|
            lines << "  - #{cell['check_kind']}: #{cell['outcome']}" \
                     "#{cell['framework'] ? " on #{cell['framework']}" : ''} " \
                     "(#{cell['environment_digest']})"
            # **How to run the same examination yourself, when the cell carries one.** It is
            # untrusted third-party code — the service never executes it — and the status says
            # whether it is runnable, a description with no command, or a format this build does
            # not know.
            reproduction = cell["reproduction"]
            next unless reproduction.is_a?(Hash)

            lines << "    reproduction: #{reproduction['status']}" \
                     "#{reproduction['command'] ? " — #{reproduction['command']}" : ''}"
          end
        end
        documented = self.class.need(body, "documented")
        unless documented.empty?
          lines << ""
          lines << "#{documented.length} documented change(s) from the release's own notes " \
                   "(readings, not executions):"
          documented.each do |change|
            named = change["subject"] || "a change it does not name"
            lines << "  - #{change['kind']} at #{change['version']}: #{named}"
            lines << "    #{change['detail']}" if change["detail"]
          end
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **A release's own words, and what a model read in them.** The documented half of an upgrade:
      # a changelog says what a symbol diff cannot, and the answer keeps the quote and the
      # provenance so a reader checks the reading rather than trusting it.
      def get_release_notes(args)
        params = { "library" => args["library"] }
        params["version"] = args["version"] if args["version"]
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params["kind"] = args["kind"] if args["kind"]
        body = @client.request("GET", "/api/releases/documented", params: params)

        lines = ["#{self.class.need(body, 'library')} documented changes"]
        items = self.class.need(body, "items")
        lines << "no documented change is recorded for this library." if items.empty?
        items.each do |change|
          named = change["subject"] || "a change it does not name"
          reviewed = change["reviewed"] ? ", reviewed" : ", not reviewed"
          lines << ""
          lines << "- #{change['kind']} at #{change['version']}: #{named}#{reviewed}"
          lines << "  #{change['detail']}" if change["detail"]
          lines << "  quote: #{change['quote']}"
          lines << "  from #{change['extracted_by'] || 'an unrecorded reader'}" \
                   "#{change['confidence'] ? ", confidence #{change['confidence']}" : ''}"
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **Who declares a dependency on a library, read backwards.**
      #
      # The corpus holds what a release needs; this is what needs it, and it is the question an
      # upgrade asks. The requirements are the source's own statements — `plan_gem_moves` is what
      # says whether one is satisfied.
      def list_dependents(args)
        params = { "library" => args["library"] }
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params["limit"] = args["limit"] if args["limit"]
        body = @client.request("GET", "/api/releases/dependents", params: params)

        lines = ["#{self.class.need(body, 'count')} recorded release(s) depend on " \
                 "#{self.class.need(body, 'dependency')} " \
                 "(#{self.class.need(body, 'ecosystem')})"]
        dependents = self.class.need(body, "dependents")
        lines << "nothing recorded names this dependency." if dependents.empty?
        dependents.each do |dependent|
          lines << "- #{dependent['library']}: #{Array(dependent['versions']).join(', ')} " \
                   "requires #{Array(dependent['requirements']).join(', ')}"
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

      # **The registry, and what it would change, without changing it.** A fix plan is a read: the
      # mechanical rewrites are applied to a copy of the files the caller sent, and the answer is a
      # line diff. A `needs_review` or `forbidden` row is listed and never applied, because the
      # service serves the registry and the client is the safety boundary. Nothing is written.
      def plan_fixes(args)
        params = {}
        params["change_key"] = args["change_key"] if args["change_key"].to_s != ""
        params["language"] = args["language"] if args["language"].to_s != ""
        body = @client.request("GET", "/api/fixes", authenticated: true, params: params)
        fixes = self.class.need(body, "fixes")
        count = self.class.need(body, "count")
        lines = ["#{count} fix(es) in the registry"]
        lines << "no row means this change has no typed fix — not that it is safe" if fixes.empty?

        fixes.each do |fix|
          payload = fix["payload"].is_a?(Hash) ? fix["payload"] : {}
          detail = if fix["kind"] == "rewrite"
            "#{payload['old']} -> #{payload['new']}"
          else
            fix["kind"].to_s
          end
          marks = fix["applies"] ? "" : " (not applicable)"
          lines << "- #{fix['change_key']} [#{fix['authority']}] " \
                   "#{fix['safety']}#{marks}: #{detail}"
        end

        files = Array(args["files"]).grep(Hash)
        mechanical = fixes.select { |fix| fix["safety"] == "mechanical" && fix["applies"] }
        changed = 0
        files.each do |file|
          path = file["path"].to_s
          next if path.empty?

          before = file["content"].to_s
          after = before.dup
          applied = []
          mechanical.each do |fix|
            payload = fix["payload"].is_a?(Hash) ? fix["payload"] : {}
            old = payload["old"].to_s
            new = payload["new"].to_s
            next if old.empty? || old == new
            next unless after.match?(/\b#{Regexp.escape(old)}\b/)

            after = after.gsub(/\b#{Regexp.escape(old)}\b/, new)
            applied << fix
          end
          next if after == before

          changed += 1
          lines << ""
          lines << "--- a/#{path}"
          lines << "+++ b/#{path}"
          before.lines.each_with_index do |old_line, index|
            new_line = after.lines[index].to_s
            next if new_line == old_line

            lines << "@@ line #{index + 1} @@"
            lines << "-#{old_line.chomp}"
            lines << "+#{new_line.chomp}"
          end
          lines << "applied: #{applied.map { |fix| fix['change_key'] }.join(', ')}"
        end

        if files.empty?
          lines << ""
          lines << "no files were sent; this is the registry only."
        elsif changed.zero?
          lines << ""
          lines << "no mechanical fix changes the files you sent."
        end
        lines << ""
        lines << "nothing was written."
        Rendering.wrap(lines.join("\n"))
      end
    end
  end
end
