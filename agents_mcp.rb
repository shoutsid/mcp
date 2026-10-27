# frozen_string_literal: true

# The path `/.well-known/agents.json` names as this service's MCP server.
#
# The real entrypoint is `bin/agents-mcp`, which selects the component's bundle; this file
# exists because the discovery document — a recorded contract this repository does not edit by hand
# — points at it, and a documented command that stopped working would be a lie in a document whose
# job is to describe the surface. It loads the wrapper rather than repeating its bundle setup, so
# there is still one entrypoint and this is a path to it.
load File.expand_path("bin/agents-mcp", __dir__)
