# frozen_string_literal: true

module AgentsFyiMcp
  class Tools
    # The rails tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module RailsUpgrade
      # The ladder itself: where it starts, where it tops out, and one row per step with its
      # Ruby floor and how much of its chapter is written down. This is the read that lets
      # a caller name a target before asking for a plan, and it describes the digest rather
      # than computing anything about the caller's move.
      def rails_ladder(_args = {})
        body = @client.request("GET", "/api/rails/ladder")
        counts = self.class.need(body, "counts")
        lines = [
          "Rails #{self.class.need(body, 'earliest')} through #{self.class.need(body, 'top')} " \
          "in #{Rendering.py(counts.fetch('steps', 0))} step(s): " \
          "#{Rendering.py(counts.fetch('documented', 0))} documented change(s) from Rails' own " \
          "upgrade guide, #{Rendering.py(counts.fetch('automatic', 0))} of them whole-word " \
          "rewrites a machine may apply",
        ]
        self.class.need(body, "steps").each do |step|
          row = +"#{step['to_version'].ljust(7)} ← #{step['from_version'].ljust(7)}"
          row << " Ruby #{step['requires_ruby']}+" if step["requires_ruby"].to_s != ""
          step_counts = step["counts"] || {}
          row << " — #{Rendering.py(step_counts.fetch('documented', 0))} documented, " \
                 "#{Rendering.py(step_counts.fetch('manual', 0))} needing a decision"
          lines << row
        end
        lines << self.class.need(body, "next_step")
        lines.join("\n")
      end

      def rails_upgrade_plan(args)
        params = { "from_version" => args["from_version"], "to_version" => args["to_version"] }

        body = @client.request("GET", "/api/rails/upgrade", params: params)
        lines = [
          "Rails #{self.class.need(body, 'from_version')} -> #{self.class.need(body, 'to_version')}",
          "#{self.class.need(body, 'documented')} documented change(s) from Rails' own " \
          "upgrade guide, #{self.class.need(body, 'observed')} observed change(s) this " \
          "corpus executed",
        ]
        if body["unplaced"]
          lines << "#{body['unplaced']} report(s) about these components could not be " \
                   "placed in a step: the release they name cannot be ordered."
        end
        if body["truncated"]
          lines << "a component holds more reports than one plan reads — the observed lists are partial"
        end

        self.class.need(body, "steps").each do |step|
          lines << ""
          lines << "== #{step['name']}: #{step['from_version']} -> #{step['to_version']}"
          if step["requires_ruby"]
            lines << "   requires Ruby #{step['requires_ruby']} or newer — move Ruby first and " \
                     "Rails after it"
          end
          lines << "   #{step['note']}" if step["note"]

          changes = step["changes"] || []
          lines << "   documented (Rails' own guide): #{changes.length}"
          changes.each do |change|
            marks = []
            if change["automatic"]
              marks << "automatic rename — find_rails_edits applies it"
            end
            if change["findable"] == false
              # The one gap a scan cannot report, so it is said here rather than left
              # out: a configuration default or a file to create has no call site.
              marks << "no call site in source — a scan will not find this"
            end
            marks << "raises by your target" if change["enforced_in_your_move"]
            mark = marks.empty? ? "" : "  [#{marks.join('; ')}]"
            went = change["replacement"] ? " -> #{change['replacement']}" : ""
            still = change["removed_in"] ? " (still works until #{change['removed_in']})" : ""
            lines << "   - #{change['kind']}: #{change['subject']}#{went}#{still}#{mark}"
            lines << "     #{change['note']}" if change["note"]
            lines << "     source: #{change['source']}" if change["source"]
          end

          observed = step["observed"] || []
          lines << "   observed (executed here): #{observed.length}"
          observed.each do |change|
            when_ = "broke in #{change['broken_in']}"
            when_ += ", still worked in #{change['from_version']}" if change["from_version"]
            named = change["subject"] || "a name it does not record"
            lines << "   - #{change['change_kind']}: #{named}"
            lines << "     #{when_} | #{change['status']} | trust #{Rendering.py(change['trust'])}"
            lines << "     report_id #{change['report_id']} | #{change['title']}"
          end
          if step["observed_unclassified"]
            lines << "   #{step['observed_unclassified']} report(s) at releases in this window " \
                     "are not recorded as changes — unrecorded, not safe."
          end
          lines << "   #{step['guidance']}"
        end

        components = body["components"] || []
        unless components.empty?
          lines << ""
          lines << "observed half read from: #{components.join(', ')}"
        end
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      def find_rails_edits(args)
        parsed = Rendering.split_files(args["files"])
        if parsed.empty?
          raise ToolError,
            "no file was found in `files`: start each one with a line of `### ` and its " \
            "path, e.g. `### app/controllers/users_controller.rb`, then the file's text " \
            "underneath. A file with no header cannot be named in the edits this tool returns."
        end
        body = @client.request(
          "POST", "/api/rails/scan",
          json: {
            "from_version" => args["from_version"], "to_version" => args["to_version"],
            "files" => parsed
          }
        )
        render_scan(body)
      end

      # **The same scan over what moved, against a manifest the caller keeps.** The service
      # stores nothing: `known` is the caller's own list of `{path, sha256, size}` rows, and only
      # the added and changed files are read. `deleted` names the paths it removed, because a path
      # it did not send is not a path it deleted.
      def scan_upgrade_delta(args)
        parsed = Rendering.split_files(args["files"].to_s)
        deleted = args["deleted"].to_s.split(",").map(&:strip).reject(&:empty?)
        if parsed.empty? && deleted.empty?
          raise ToolError,
            "nothing would be read: send files in the `### path` form, or name the paths you " \
            "deleted. A delta with neither is a request with nothing to answer."
        end
        known = Array(args["known"]).filter_map do |row|
          next nil unless row.is_a?(Hash)

          path = row["path"].to_s
          sha = row["sha256"].to_s
          next nil if path.empty? || sha.empty?

          { "path" => path, "sha256" => sha, "size" => row["size"].to_i }
        end
        body = @client.request(
          "POST", "/api/rails/scan/delta",
          json: {
            "from_version" => args["from_version"], "to_version" => args["to_version"],
            "files" => parsed, "known" => known, "deleted" => deleted
          }
        )
        render_scan(body)
      end

      # One rendering for both scan routes, so a hit and its delta are read the same way.
      def render_scan(body)
        counts = self.class.need(body, "counts")
        lines = [
          "Rails #{self.class.need(body, 'from_version')} -> #{self.class.need(body, 'to_version')}",
          "#{self.class.need(body, 'files_read')} file(s), #{self.class.need(body, 'lines_read')} " \
          "line(s) read: #{counts.fetch('automatic', 0)} automatic edit(s), " \
          "#{counts.fetch('manual', 0)} call site(s) to decide",
        ]
        lines << "the scan stopped at its bound: no further call sites are listed" if body["truncated"]
        delta = body["delta"]
        if delta.is_a?(Hash)
          lines << "delta: #{Array(delta['added']).length} added, " \
                   "#{Array(delta['changed']).length} changed, " \
                   "#{Array(delta['unchanged']).length} unchanged, " \
                   "#{Array(delta['deleted']).length} deleted, " \
                   "#{delta['skipped'].to_i} skipped (not re-read)"
        end

        edits = self.class.need(body, "edits")
        unless edits.empty?
          lines << ""
          lines << "apply these (whole-word renames):"
          edits.each do |edit|
            lines << "  #{edit['path']}:#{edit['line']}"
            # Both lines as they are, indentation included: this is a diff to review
            # before it is applied, and the leading whitespace is part of what tells
            # the caller where in the file it lands.
            lines << "  - #{edit['text']}"
            lines << "  + #{edit['after']}"
          end
        end

        manual = self.class.need(body, "manual")
        unless manual.empty?
          lines << ""
          lines << "decide these by hand (no safe substitution exists):"
          manual.each do |edit|
            lines << "  #{edit['path']}:#{edit['line']} — #{edit['subject']} (#{edit['kind']})"
            lines << "     want: #{edit['replacement']}" if edit["replacement"]
            lines << "     #{edit['note']}" if edit["note"]
            lines << "     line: #{edit['text']}"
          end
        end

        if edits.empty? && manual.empty?
          lines << ""
          lines << "no call site of any change this move crosses was found in these files — " \
                   "which is not the same as nothing to do. Changes that cannot be found in " \
                   "source (a configuration default, a file to create) are listed per step by " \
                   "rails_upgrade_plan."
        end
        lines << ""
        lines << "stored: no (your files were read to answer this and kept nowhere)"
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end
    end
  end
end
