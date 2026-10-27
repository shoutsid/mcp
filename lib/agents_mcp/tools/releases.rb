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
    end
  end
end
