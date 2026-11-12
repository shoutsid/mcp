# frozen_string_literal: true

module AgentsMcp
  class Tools
    # The releases tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module Releases
      def check_lockfile_ruby_compatibility(args)
        body = @client.request(
          "POST", "/api/releases/lockfile",
          json: { "ecosystem" => "ruby", "ruby" => args["ruby"], "lockfile" => args["lockfile"] }
        )
        counts = self.class.need(body, "counts")
        lines = [
          "#{self.class.need(body, 'gems_read')} gem(s) pinned, " \
          "checked against Ruby #{self.class.need(body, 'ruby')}:",
          "compatible #{Rendering.py(counts.fetch('compatible', 0))}, " \
          "incompatible #{Rendering.py(counts.fetch('incompatible', 0))}, " \
          "unknown #{Rendering.py(counts.fetch('unknown', 0))}",
        ]
        self.class.need(body, "gems").each do |gem|
          next unless gem["compatible"] == false

          lines << "  NO  #{gem['name']} #{gem['version']}: #{gem['reason']}"
        end
        self.class.need(body, "gems").each do |gem|
          next unless gem["compatible"].nil?

          lines << "  ?   #{gem['name']} #{gem['version']}: #{gem['reason']}"
        end
        lines << "stored: no (the lockfile was read to answer and not kept)"
        lines.join("\n")
      end

      def check_ruby_compatibility(args)
        body = @client.request(
          "GET", "/api/releases/compatibility",
          params: {
            "library" => args["library"], "version" => args["version"],
            "ruby" => args["ruby"], "ecosystem" => "ruby"
          }
        )
        verdict = { true => "yes", false => "no", nil => "unknown" }[body["compatible"]]
        lines = [
          "#{self.class.need(body, 'library')} #{self.class.need(body, 'version')} " \
          "on Ruby #{self.class.need(body, 'ruby')}: #{verdict}",
          "reason: #{self.class.need(body, 'reason')}",
        ]
        lines << "declared requirement: #{body['ruby_requirement']}" if body["ruby_requirement"]
        lines.join("\n")
      end

      # **The whole-lockfile brief.** One read answers for every pin what the corpus holds between
      # what the lock has and the newest recorded release: a recorded change with its fix, an
      # examined cell that came back clean, or nothing at all. The rendering puts the blocking gems
      # first, then the unknown space, because those are the two a caller acts on.
      def brief_dependencies(args)
        payload = { "ecosystem" => "ruby", "lockfile" => args["lockfile"] }
        payload["ruby"] = args["ruby"] if args["ruby"]
        payload["rails"] = args["rails"] if args["rails"]
        payload["symbols"] = args["symbols"] if args["symbols"]
        payload["targets"] = args["targets"] if args["targets"]
        payload["checks"] = args["checks"] unless args["checks"].nil?
        body = @client.request("POST", "/api/releases/impact", json: payload)

        counts = self.class.need(body, "counts")
        lines = [
          "#{self.class.need(body, 'gems_read')} gem(s) pinned; " \
          "blocking #{Rendering.py(counts.fetch('blocking', 0))}, " \
          "review #{Rendering.py(counts.fetch('review', 0))}, " \
          "clean #{Rendering.py(counts.fetch('clean', 0))}, " \
          "unknown #{Rendering.py(counts.fetch('unknown', 0))}",
        ]
        lines << "the lockfile was read to answer and not kept (stored: false)"

        gems = self.class.need(body, "gems")
        %w[blocking review clean unknown].each do |verdict|
          selected = gems.select { |gem| gem["verdict"] == verdict }
          next if selected.empty?

          lines << ""
          lines << "#{verdict.upcase}:"
          selected.first(25).each { |gem| lines.concat(brief_gem(gem)) }
          lines << "  … #{selected.length - 25} more" if selected.length > 25
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **How much of a library the corpus has actually looked at.** The negative space of
      # `check_upgrade`: the windows examined, their outcomes, and the adjacent pairs nobody has run.
      def check_coverage(args)
        params = { "library" => args["library"] }
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params["version"] = args["version"] if args["version"]
        params["limit"] = args["limit"] if args["limit"]
        body = @client.request("GET", "/api/releases/coverage", params: params)

        counts = self.class.need(body, "counts")
        lines = [
          "#{self.class.need(body, 'library')} (#{self.class.need(body, 'ecosystem')}): " \
          "#{Rendering.py(counts.fetch('known_releases', 0))} recorded release(s), " \
          "#{Rendering.py(counts.fetch('windows_examined', 0))} examined window(s), " \
          "#{Rendering.py(counts.fetch('windows_missing', 0))} never examined",
        ]
        if body["empty_reason"]
          lines << "empty: #{body['empty_reason']}"
        end
        Array(body["windows"]).each do |window|
          lines << "  #{window['from_version']} -> #{window['to_version']}: " \
                   "clean #{Rendering.py(window.fetch('clean', 0))}, " \
                   "findings #{Rendering.py(window.fetch('findings', 0))}, " \
                   "unexaminable #{Rendering.py(window.fetch('unexaminable', 0))}, " \
                   "failed #{Rendering.py(window.fetch('failed', 0))} " \
                   "(#{Array(window['checks']).join(', ')})"
        end
        missing = Array(body["unexamined"])
        unless missing.empty?
          lines << "never examined:"
          missing.first(10).each do |pair|
            lines << "  #{pair['from_version']} -> #{pair['to_version']}"
          end
        end
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **A caller asking for a window to be examined.** The write that turns "my gem is not in it"
      # into work: an operator key is required and an agent key is refused, the same rule every
      # mining-queue write keeps.
      def request_examination(args)
        payload = { "ecosystem" => args["ecosystem"] || "ruby", "library" => args["library"],
                    "from_version" => args["from_version"], "to_version" => args["to_version"] }
        payload["reason"] = args["reason"] if args["reason"]
        body = @client.request("POST", "/api/mining/requests", json: payload, authenticated: true)

        lines = [
          "requested #{self.class.need(body, 'library')} " \
          "#{self.class.need(body, 'from_version')} -> #{self.class.need(body, 'to_version')}",
          "state: #{self.class.need(body, 'state')}#{body['created'] == false ? ' (already asked)' : ''}",
          "expires: #{self.class.need(body, 'expires_at')}",
        ]
        lines << "reason: #{body['reason']}" if body["reason"]
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # **The requests, live and historical.** A read, so a caller can see what is waiting without
      # holding a key.
      def list_examination_requests(args)
        params = {}
        params["ecosystem"] = args["ecosystem"] if args["ecosystem"]
        params["library"] = args["library"] if args["library"]
        params["state"] = args["state"] if args["state"]
        params["limit"] = args["limit"] if args["limit"]
        body = @client.request("GET", "/api/mining/requests", params: params)

        lines = ["#{self.class.need(body, 'total')} request(s) on #{self.class.need(body, 'ecosystem')}"]
        items = self.class.need(body, "items")
        lines << "nothing has been asked for here." if items.empty?
        items.first(25).each do |item|
          line = +"  #{item['library']} #{item['from_version']} -> #{item['to_version']}: #{item['state']}"
          line << " (examination #{item['examination_id']})" if item["examination_id"]
          line << " — #{item['refused_reason']}" if item["refused_reason"]
          lines << line        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      # The per-gem lines the brief renders, kept out of the method above so the four verdict
      # sections share one shape. Not `private`: a `private` here would hide every method after it
      # in this module, which is how the releases tools are included into `Tools`.
      def brief_gem(gem)
        heading = +"  #{gem['name']} #{gem['version']}"
        heading << " -> #{gem['target']}" if gem["target"]
        heading << " (#{gem['target_source']})" if gem["target_source"] == "requested"
        out = [heading]
        out << "    a request to examine this window is already open" if gem["requested"]
        Array(gem["changes"]).first(5).each do |change|
          named = change["subject"] || "a change it does not name"
          marks = change["affects_your_code"] == true ? "  <-- yours" : ""
          out << "    - #{change['change_kind']}: #{named} (broke in #{change['broken_in']})#{marks}"
          out << "      report_id #{change['report_id']} | #{change['title']}"
        end
        out << "    #{gem['reason']}" if gem["reason"]
        clean = Array(gem["clean"]).length
        out << "    #{clean} examined cell(s) came back clean" if clean.positive?
        out
      end

      # The gem-migrations digest, as a sentence a caller can act on: which of the gems it
      # holds a machine may move without reading the code, and which need a decision.
      #
      # The digest is the *documented* half of gem upgrades (a claim about an index and a
      # repository, each entry naming where it was read from), and the rendering keeps that
      # visible rather than presenting it as a compatibility check: what executing two
      # releases establishes lives in `check_upgrade`.
      def gem_migrations(args)
        requested = args["gems"].to_s.strip
        body = @client.request("GET", "/api/gems/migrations",
          params: requested.empty? ? nil : { "gems" => requested })
        migrations = self.class.need(body, "migrations")
        counts = self.class.need(body, "counts")
        lines = ["#{Rendering.py(counts.fetch('selected', 0))} of " \
                 "#{Rendering.py(counts.fetch('total', 0))} migration(s) apply."]
        migrations.each do |migration|
          heading = +"#{migration['gem']} — #{migration['kind']}"
          if migration["replacement"]
            heading << " #{migration['replacement']}"
            heading << " #{migration['requirement']}" if migration["requirement"]
          end
          heading << (migration["mechanical"] ? " [a machine may make this change]" : " [a decision]")
          lines << heading
          lines << "    #{migration['note']}"
          lines << "    read from: #{migration['source']}"
        end
        lines << self.class.need(body, "next_step")
        lines.join("\n")
      end

      # What each pin of a lockfile needs before a Rails move can be installed: the routing
      # half of gem upgrades, rendered so the two kinds of answer a caller acts on — the
      # gems that have somewhere to go, and the ones nothing is known about — are apart.
      def plan_gem_moves(args)
        body = @client.request(
          "POST", "/api/releases/route",
          json: { "ecosystem" => "ruby", "ruby" => args["ruby"], "rails" => args["rails"],
                  "lockfile" => args["lockfile"] }
        )
        counts = self.class.need(body, "counts")
        lines = [
          "#{self.class.need(body, 'gems_read')} gem(s) pinned, routed for Ruby " \
          "#{self.class.need(body, 'ruby')} and Rails #{self.class.need(body, 'rails')}:",
          "keep #{Rendering.py(counts.fetch('keep', 0))}, " \
          "move #{Rendering.py(counts.fetch('move', 0))}, " \
          "replace #{Rendering.py(counts.fetch('replace', 0))}, " \
          "remove #{Rendering.py(counts.fetch('remove', 0))}, " \
          "blocked #{Rendering.py(counts.fetch('blocked', 0))}, " \
          "unknown #{Rendering.py(counts.fetch('unknown', 0))}",
        ]
        self.class.need(body, "gems").each do |gem|
          next if gem["verdict"] == "keep"

          heading = +"#{gem['verdict'].upcase}  #{gem['name']} #{gem['version']}"
          heading << " -> #{gem['to']}" if gem["to"]
          if gem["replacement"]
            heading << " -> #{gem['replacement']}"
            heading << " #{gem['requirement']}" if gem["requirement"]
          end
          lines << heading
          lines << "    #{gem['reason']}" if gem["reason"]
          lines << "    #{gem['note']}" if gem["note"]
          lines << "    read from: #{gem['source']}" if gem["source"]
        end
        lines << self.class.need(body, "next_step")
        lines.join("\n")
      end

      def record_release_facts(args)
        parsed = []
        Rendering.lines(args["facts"]).each do |line|
          next if line.strip.empty?

          version, _, requirement = line.partition("=")
          parsed << {
            "version" => version.strip,
            "ruby_requirement" => requirement.strip.empty? ? nil : requirement.strip,
          }
        end
        raise ToolError, "no releases were given: send one `version=requirement` line per release." if parsed.empty?

        recorded = 0
        requests = 0
        (0...parsed.length).step(Rendering::RELEASE_FACTS_PAGE) do |start|
          body = @client.request(
            "POST", "/api/releases/facts",
            json: {
              "ecosystem" => "ruby", "library" => args["library"],
              "facts" => parsed[start, Rendering::RELEASE_FACTS_PAGE]
            },
            authenticated: true
          )
          recorded += self.class.need(body, "recorded")
          requests += 1
        end
        "Recorded #{recorded} release(s) of #{args['library']} in #{requests} request(s)."
      end

      # `get_release`: one release's changes, grouped by the change rather than by the report.
      #
      # This is the read that answers "what changed at 7.1" without a search for the version string
      # and a read of every hit: three reports about one renamed method come back as one change with
      # three witnesses, and an empty answer says whether the library is unknown to this corpus or
      # merely recorded at other versions.
      def get_release(args)
        body = @client.request("GET", @client.release_path(args["ecosystem"], args["library"],
          args["version"]))
        # Wrapped like every read that hands a model report titles: the change keys are the corpus's,
        # the titles inside them were written by whoever filed the report.
        Rendering.wrap(Rendering.render_release(body))
      end
    end
  end
end
