# frozen_string_literal: true

module AgentsMcp
  class Tools
    # The reports tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module Reports
      def precheck_report(args)
        payload = {}
        {
          "title" => args["title"], "library" => args["library"], "version" => args["version"],
          "problem" => args["problem"], "resolution" => args["resolution"], "trace" => args["trace"]
        }.each { |field, value| payload[field] = value if value }
        # Sent only when it is not the default, so a body is still exactly what the
        # description promises for the common case.
        subject_kind = args.fetch("subject_kind", "package")
        payload["subject_kind"] = subject_kind if subject_kind && subject_kind != "package"
        payload["ecosystem"] = args["ecosystem"] if args["ecosystem"] && args["ecosystem"] != "python"

        body = @client.request("POST", "/api/reports/precheck", json: payload, params: nil)
        lines = ["verdict: #{self.class.need(body, 'verdict')}",
                 "advice: #{self.class.need(body, 'advice')}"]
        lines << "symptoms_in_your_draft: #{body['signatures'].join(', ')}" if body["signatures"]
        read = body["trace"]
        if read
          # Report what was understood from the evidence, including the fields it
          # supplied and any disagreement with what was declared.
          lines << "read_from_trace: #{read['exception']}" if read["exception"]
          if read["library"] || read["version"]
            lines << "trace_identifies: " + [read["library"], read["version"]].compact.join(", ")
          end
          (read["notes"] || []).each { |note| lines << "note: #{note}" }
        end

        candidates = body["candidates"] || []
        return lines.join("\n") if candidates.empty?

        lines << ""
        lines << "closest existing reports:"
        candidates.each do |candidate|
          lines << "  - report_id #{candidate['id']} | #{candidate['status']} | " \
                   "trust #{Rendering.py(candidate['trust'])} | " \
                   "title similarity #{Rendering.py(candidate['similarity'])} | " \
                   "symptom overlap #{Rendering.py(candidate['signature_overlap'])}"
          lines << "    title: #{candidate['title']}"
          if candidate["matched_signatures"]
            lines << "    shared symptoms: #{candidate['matched_signatures'].join(', ')}"
          end
        end

        Rendering.wrap(lines.join("\n"))
      end

      def triage_failures(args)
        payload = { "items" => args["failures"] }
        payload["library"] = args["library"] if args["library"]
        payload["version"] = args["version"] if args["version"]
        subject_kind = args.fetch("subject_kind", "package")
        payload["subject_kind"] = subject_kind if subject_kind && subject_kind != "package"
        # A run is one index as well as one project: an entry that fell back to PyPI
        # would be compared against the wrong corpus, silently.
        payload["ecosystem"] = args["ecosystem"] if args["ecosystem"] && args["ecosystem"] != "python"
        body = @client.request("POST", "/api/reports/triage", json: payload, params: nil)
        summary = self.class.need(body, "summary")

        lines = [
          "#{self.class.need(summary, 'items')} failures: #{self.class.need(summary, 'new')} new, " \
          "#{self.class.need(summary, 'duplicates')} already recorded, " \
          "#{self.class.need(summary, 'similar')} worth reading " \
          "(#{Rendering.py_round(self.class.need(summary, 'known_share') * 100)}% of this run is known).",
          "advice: #{self.class.need(summary, 'advice')}",
        ]
        self.class.need(body, "items").each do |item|
          lines << ""
          lines << "#{item['index'] + 1}. [#{item['action']}] #{item['title']}"
          if item["action"] == "submit"
            # The fields the report would be filed under, read from the evidence, so
            # submitting is a decision rather than another parse of the trace. The
            # kind is named only when it is not a package.
            kind = item["subject_kind"] || "package"
            suffix = kind == "package" ? "" : " (about a #{kind})"
            lines << "   file as: #{item['library']} #{item['version']}#{suffix}"
          end
          candidate = item["candidate"]
          if candidate
            lines << "   report_id #{candidate['id']} | #{candidate['status']} | " \
                     "trust #{Rendering.py(candidate['trust'])} | " \
                     "title similarity #{Rendering.py(candidate['similarity'])}"
            if candidate["matched_signatures"]
              lines << "   shared symptoms: #{candidate['matched_signatures'].join(', ')}"
            end
          end
          lines << "   #{item['advice']}"
          (item["notes"] || []).each { |note| lines << "   note: #{note}" }
        end

        Rendering.wrap(lines.join("\n"))
      end

      def submit_report(args)
        payload = {}
        {
          "title" => args["title"], "library" => args["library"], "version" => args["version"],
          "problem" => args["problem"], "resolution" => args["resolution"],
          "attempted" => args["attempted"], "environment" => args["environment"],
          "trace" => args["trace"]
        }.each { |field, value| payload[field] = value if value }
        # Sent only when it says something the default does not. A traceback-only
        # submission is a documented shape of the call, and a field carried on the
        # wire because a tool defaulted it would make that shape noisier.
        subject_kind = args.fetch("subject_kind", "package")
        payload["subject_kind"] = subject_kind if subject_kind && subject_kind != "package"
        payload["ecosystem"] = args["ecosystem"] if args["ecosystem"] && args["ecosystem"] != "python"

        report = @client.request("POST", "/api/reports", authenticated: true, json: payload)
        "Submitted report #{self.class.need(report, 'id')} with status " \
          "#{self.class.need(report, 'status')}. " \
          "It becomes resolved_verified once other operators reproduce it."
      end

      def submit_reports(args)
        payload = { "items" => args["findings"] }
        payload["library"] = args["library"] if args["library"]
        payload["version"] = args["version"] if args["version"]
        subject_kind = args.fetch("subject_kind", "package")
        payload["subject_kind"] = subject_kind if subject_kind && subject_kind != "package"
        payload["ecosystem"] = args["ecosystem"] if args["ecosystem"] && args["ecosystem"] != "python"
        body = @client.request("POST", "/api/reports/batch", authenticated: true, json: payload)
        summary = self.class.need(body, "summary")

        lines = [
          "#{self.class.need(summary, 'items')} findings: #{self.class.need(summary, 'created')} " \
          "filed, #{self.class.need(summary, 'duplicates')} already recorded, " \
          "#{self.class.need(summary, 'rejected')} refused.",
          "advice: #{self.class.need(summary, 'advice')}",
        ]
        self.class.need(body, "items").each do |item|
          lines << ""
          title = item["title"].to_s
          lines << "#{item['index'] + 1}. [#{item['status']}] #{title.empty? ? '(no title)' : title}"
          lines << "   report_id: #{item['report_id']}" if item["report_id"]
          if item["status"] == "duplicate"
            lines << "   already recorded: verify that report rather than filing it again."
          elsif item["detail"]
            lines << "   #{item['detail']}"
          end
          (item["notes"] || []).each { |note| lines << "   note: #{note}" }
        end

        Rendering.wrap(lines.join("\n"))
      end
    end
  end
end
