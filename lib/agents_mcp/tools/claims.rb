# frozen_string_literal: true

module AgentsMcp
  class Tools
    # The claims tools' behaviour. The method names are the names `HANDLERS` dispatches
    # to, so nothing in the behaviour suite moved when this file was split out.
    module Claims
      def claim_report(args)
        report_id = args["report_id"]
        result = @client.request("POST", @client.report_path(report_id, "/claim"), authenticated: true)
        claim = result["claim"] || {}
        "#{result['action']} #{report_id} (held=#{Rendering.py(claim['held'])}, " \
          "yours=#{Rendering.py(claim['yours'])}, expires #{Rendering.py(claim['expires_at'])}, " \
          "status=#{result['status']}). #{result['next_step']}"
      end

      def release_report(args)
        report_id = args["report_id"]
        result = @client.request("POST", @client.report_path(report_id, "/release"), authenticated: true)
        claim = result["claim"] || {}
        "#{result['action']} #{report_id} (held=#{Rendering.py(claim['held'])}, " \
          "status=#{result['status']}). #{result['next_step']}"
      end

      def verify_report(args)
        payload = { "outcome" => args["outcome"] }
        payload["environment"] = args["environment"] if args["environment"]
        payload["notes"] = args["notes"] if args["notes"]

        report_id = args["report_id"]
        result = @client.request(
          "POST", @client.report_path(report_id, "/verify"), authenticated: true, json: payload
        )
        report = result["report"] || {}
        "Recorded #{args['outcome']} for #{report_id}. " \
          "status=#{report['status']} " \
          "confirmations=#{result['confirmations']}/#{result['confirmations_required']} " \
          "counted_toward_promotion=#{Rendering.py(result['counted'])}"
      end

      def record_outcome(args)
        payload = { "outcome" => args["outcome"] }
        payload["note"] = args["note"] if args["note"]
        payload["resolution_id"] = args["resolution_id"] if args["resolution_id"]

        report_id = args["report_id"]
        result = @client.request(
          "POST", @client.report_path(report_id, "/outcome"), authenticated: true, json: payload
        )
        "Recorded #{args['outcome']} for #{report_id} (counted=#{Rendering.py(result['counted'])}, " \
          "applied_to=#{Rendering.py(result['applied_to'])}). " \
          "usefulness=#{Rendering.py(result['usefulness'])} trust=#{Rendering.py(result['trust'])} " \
          "status=#{result['status']} " \
          "[solved #{result['solved_count']}, partial #{result['partial_count']}, " \
          "not_helpful #{result['not_helpful_count']}]"
      end

      def flag_report(args)
        payload = { "reason" => args["reason"] }
        payload["detail"] = args["detail"] if args["detail"]

        report_id = args["report_id"]
        result = @client.request(
          "POST", @client.report_path(report_id, "/flag"), authenticated: true, json: payload
        )
        "Flagged #{report_id} as #{result['reason']}. " \
          "flags=#{result['flag_count']}/#{result['hide_threshold']} " \
          "hidden=#{Rendering.py(result['hidden'])}"
      end

      def propose_resolution(args)
        payload = { "resolution" => args["resolution"] }
        payload["environment"] = args["environment"] if args["environment"]
        payload["notes"] = args["notes"] if args["notes"]

        report_id = args["report_id"]
        result = @client.request(
          "POST", @client.report_path(report_id, "/resolution"), authenticated: true, json: payload
        )
        report = result["report"] || {}
        # The API's own sentence, rather than a second wording here: whether a fix
        # was adopted, kept as an alternative, or is the caller's own proposal
        # revised are three different outcomes, and a summary composed here could
        # disagree with it.
        "Fix recorded for #{report_id}. #{result['detail']} " \
          "promoted=#{Rendering.py(result['promoted'])} " \
          "status=#{result['status']} " \
          "confirmations=#{result['confirmations']}/#{result['confirmations_required']} " \
          "proposals=#{result['proposals']} " \
          "source=#{report['resolution_source']}\nnext: #{result['next_step']}"
      end
    end
  end
end
