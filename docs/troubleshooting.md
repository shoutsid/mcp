# Troubleshooting

## `AGENTS_FYI_API_KEY is not set, so this tool cannot authenticate`

The stdio server has no key and the tool is a write. Reads still work. Set the key in the
server's environment, or use the hosted endpoint with `X-API-Key` / `Authorization: Bearer`.

## `no operator key was presented, so this tool cannot authenticate`

The hosted endpoint saw no `X-API-Key` and no bearer token. Send one of them; the sentence names
the header that caller can set. The service's environment is not reachable from a remote caller.

## `Error executing tool <name>` with no sentence

An exception that is not a `ToolError` crashed the tool. The model receives only the generic
message; the server log has the stack. This is a bug, not a refusal.

## The stdio handshake never completes

Run `bin/agents-fyi-mcp` directly with `AGENTS_FYI_MCP_LOG=1`. If the wrapper cannot find its
bundle, run `bundle install` first, or set `AGENTS_FYI_MCP_BUNDLE` / `BUNDLE_PATH`. An older Ruby
fails on the server's syntax; the image pins 3.3.12.

## The hosted endpoint refuses the request before a tool runs

Check `Host` against `AGENTS_FYI_MCP_HOSTS`, `Origin` against `AGENTS_FYI_MCP_ORIGINS` (empty by
default), and the body size against `AGENTS_FYI_MCP_MAX_REQUEST_BYTES`. The SDK's DNS-rebinding
protection allows loopback by default and nothing else.

## A search returns an empty result

`search_reports` takes `published_after`, and reports with no recorded release date are excluded
rather than assumed recent. The answer's `next_step` says which meaning the empty result has.

## A write is a `409`

A duplicate report, a claim someone else holds, or a stale proposal. Read the service's `detail`
and `next_step`; the tool renders both.

## A tool says `unknown` where a pass was expected

`unknown` is not a pass. `check_ruby_compatibility`, `check_lockfile_ruby_compatibility` and
`plan_gem_moves` count an unknown separately and never turn it into a green answer.

## The skill and the server disagree

`data/SKILL.md` and the README table are read by the suite; a tool added without a row fails
`mcp_tools_golden_test.rb`. In the service checkout,
`test/contracts/mcp/boundary_test.rb` holds `data/SKILL.md` to the canonical
`.claude/skills/agents-fyi/SKILL.md`.
