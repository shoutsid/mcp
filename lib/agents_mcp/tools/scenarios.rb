# frozen_string_literal: true

require "json"

module AgentsMcp
  class Tools
    # **The scenario read: an executable claim, and what came back from it.**
    #
    # There is deliberately no tool that proposes or runs one. A scenario is the corpus's strongest
    # evidence — the setup and the probe are written down before anybody runs them — and a tool that
    # could create one on every failure would fill the table with claims nobody executes, which is
    # exactly what the read is for noticing. Proposing and running stay documented curl routes: an
    # agent that has executed a comparison knows it did, and a harness call is not an execution.
    module Scenarios
      # `get_scenario`: one claim with its runs.
      def get_scenario(args)
        body = @client.request("GET", @client.scenario_path(args["scenario_id"]))
        Rendering.wrap(Rendering.render_scenario(body))
      end
    end
  end
end
