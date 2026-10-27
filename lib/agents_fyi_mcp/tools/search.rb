# frozen_string_literal: true

module AgentsFyiMcp
  class Tools
    # The search tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module Search
      def find_answer(args)
        params = {}
        params["q"] = args["query"] if args["query"]
        params["trace"] = args["trace"] if args["trace"]
        params["library"] = args["library"] if args["library"]
        params["client_version"] = args["client_version"] if args["client_version"]
        params["signature"] = args["signature"] if args["signature"]
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params.merge!(@client.demand_params)

        body = @client.request("GET", "/api/reports/answer", params: params)
        lines = [
          "verdict: #{self.class.need(body, 'verdict')}",
          "confidence: #{self.class.need(body, 'confidence')}",
        ]

        answer = body["answer"]
        if answer.nil?
          lines << "no report in this corpus covers it."
        else
          lines << ""
          relation = self.class.need(answer, "version_relation")
          lines << "report_id: #{self.class.need(answer, 'report_id')}"
          lines << "title: #{self.class.need(answer, 'title')}"
          lines << "library: #{self.class.need(answer, 'library')} " \
                   "#{self.class.need(answer, 'version')} (#{relation})"
          lines << "status: #{self.class.need(answer, 'status')} " \
                   "trust: #{self.class.need(answer, 'trust')}"
          claimed = Rendering.claim_line(answer["claim"])
          lines << claimed if claimed
          resolution = answer["resolution"]
          lines << "resolution: #{resolution}" if resolution
          if body["fixes"]
            # Every fix on offer, not only the adopted one: a second fix that three
            # operators reported working is better advice than the first one they
            # worked around, and the caller is the one deciding.
            lines << "fixes on offer:"
            body["fixes"].each do |fix|
              # The adopted fix *is* the report's resolution, so printing the
              # paragraph again would add nothing; the line still carries what is
              # not a repeat — whether it is adopted, its record, and its id.
              text =
                if resolution && fix["resolution"] == resolution
                  "(this report's own resolution, above)"
                else
                  fix["resolution"]
                end
              lines << Rendering.render_fix_line(
                Rendering.py(fix["resolution_id"] || ""),
                text,
                adopted: fix["adopted"],
                solved: fix["solved_count"] || 0,
                partial: fix["partial_count"] || 0,
                not_helpful: fix["not_helpful_count"] || 0,
                usefulness: fix["usefulness"],
              )
            end
          end
          lines << "problem: #{self.class.need(answer, 'problem')}"
        end

        if body["reasons"]
          lines << ""
          lines << "why it is trustworthy:"
          body["reasons"].each { |reason| lines << "  - #{reason}" }
        end
        if body["caveats"]
          lines << ""
          lines << "caveats:"
          body["caveats"].each { |caveat| lines << "  - #{caveat}" }
        end
        if body["dissent"]
          lines << ""
          lines << "reports where this went badly:"
          body["dissent"].each do |item|
            lines << "  - #{item['report_id']}: #{item['reason']} (#{item['title']})"
          end
        end
        if body["alternatives"]
          lines << ""
          lines << "other reports worth reading:"
          body["alternatives"].each do |item|
            lines << "  - #{item['report_id']} | #{item['status']} | " \
                     "trust #{Rendering.py(item['trust'])} | #{item['title']}"
          end
        end
        lines << ""
        lines << "next: #{self.class.need(body, 'next_step')}"

        Rendering.wrap(lines.join("\n"))
      end

      def search_reports(args)
        params = {
          "q" => args["query"],
          "limit" => [[args.fetch("limit", 10).to_i, 1].max, 50].min,
          # Clipped by default: an agent is usually deciding whether to read further,
          # and get_report has the whole body when it wants it.
          "view" => "brief",
        }
        params["library"] = args["library"] if args["library"]
        params["version"] = args["version"] if args["version"]
        params["signature"] = args["signature"] if args["signature"]
        params["require_signature"] = "true" if args["require_signature"]
        params["subject_kind"] = args["subject_kind"] if args["subject_kind"]
        params["published_after"] = args["published_after"] if args["published_after"]
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params.merge!(@client.demand_params)

        body = @client.request("GET", "/api/reports/search", params: params)
        items = body["items"] || []
        if items.empty?
          # The service's own diagnosis, which is not the same sentence for every
          # empty page: a name it files under a different spelling, a name it has
          # never seen, or terms that simply missed.
          lines = ["No reports matched #{Rendering.py_repr(args['query'])} " \
                   "(searched #{body.fetch('total', 0)})."]
          lines << body["hint"] if body["hint"]
          lines << "If you solve this, consider submitting it."
          return Rendering.wrap(lines.join("\n\n"))
        end

        rendered = items.map { |item| Rendering.render_report(item, with_score: true) }.join("\n\n")
        Rendering.wrap(
          "#{items.length} of #{body['total']} matching reports, most relevant first.\n\n#{rendered}"
        )
      end

      def get_report(args)
        Rendering.wrap(
          Rendering.render_report(@client.request("GET", @client.report_path(args["report_id"])))
        )
      end
    end
  end
end
