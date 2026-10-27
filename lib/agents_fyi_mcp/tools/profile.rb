# frozen_string_literal: true

require "json"

module AgentsFyiMcp
  class Tools
    # **A project's profile, and a proposal to change it.** The profile decides whether a green
    # suite means anything — the command, the checks, the environment names — so a model may read
    # it and suggest fields with a source for each, and a person accepts the ones they believe.
    # There is no tool that accepts: the route exists for the account administrator.
    module Profile
      def get_project_profile(args)
        project_id = args["project_id"].to_s
        raise ToolError, "`project_id` is required" if project_id.empty?

        body = @client.request("GET",
          "/api/upgrades/projects/#{Encoding.quote(project_id, safe: '')}/profile",
          authenticated: true)
        profile = body["profile"].is_a?(Hash) ? body["profile"] : {}
        lines = [
          "#{self.class.need(body, 'name')} (#{self.class.need(body, 'slug')})",
          "repository: #{self.class.need(body, 'repo_url')}",
          "move: #{body['from_version']} -> #{body['to_version']}",
          ""
        ]
        if body["problem"]
          lines << "the profile is not walkable: #{body['problem']}"
        else
          lines << "the profile is walkable"
        end
        lines << ""
        profile.each do |name, value|
          lines << "#{name}: #{JSON.generate(value)}"
        end
        proposals = body["proposals"].is_a?(Hash) ? body["proposals"] : {}
        lines << ""
        lines << "proposals: #{proposals['proposed'].to_i} open, " \
                 "#{proposals['accepted'].to_i} accepted, #{proposals['rejected'].to_i} rejected"
        policy = body["agent_policy"].is_a?(Hash) ? body["agent_policy"] : {}
        lines << "consultant policy: #{policy['policy']} " \
                 "(capabilities #{Array(policy['capabilities']).join(', ')})"
        lines << ""
        lines << self.class.need(body, "next_step")
        Rendering.wrap(lines.join("\n"))
      end

      def propose_profile(args)
        project_id = args["project_id"].to_s
        raise ToolError, "`project_id` is required" if project_id.empty?
        fields = args["fields"]
        raise ToolError, "`fields` is required" unless fields.is_a?(Hash) && !fields.empty?

        body = @client.request("POST",
          "/api/upgrades/projects/#{Encoding.quote(project_id, safe: '')}/profile_proposals",
          authenticated: true,
          json: {
            "fields" => fields,
            "evidence" => args["evidence"].is_a?(Hash) ? args["evidence"] : {},
            "provenance" => args["provenance"].is_a?(Hash) ? args["provenance"] : {}
          })
        "Proposed profile proposal #{self.class.need(body, 'id')} for project " \
          "#{self.class.need(body, 'project_id')}, #{Array(body.dig('fields')&.keys).join(', ')}. " \
          "It applies nothing: an account administrator accepts the fields they believe."
      end
    end
  end
end
