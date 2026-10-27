# Architecture

The gem (`mcp` 1.8) is the protocol. This repository is the surface and the behavior behind it.

## The layers

| File | What it decides |
|---|---|
| `lib/agents_fyi_mcp/surface.rb` | The 32 `MCP::Tool` subclasses: name, title, description, input and output schemas, annotations. |
| `lib/agents_fyi_mcp/tools/` | What each tool does: the HTTP call, the arguments, the rendered answer. |
| `lib/agents_fyi_mcp/client.rb` | The one HTTP client, the operator key, the timeout, the refusal type. |
| `lib/agents_fyi_mcp/rendering.rb` | The untrusted-content markers around every report body. |
| `lib/agents_fyi_mcp/identity.rb` | What the server says it is: name, title, version, description, instructions. |
| `lib/agents_fyi_mcp/server.rb` | Builds the SDK server from the surface and the client. |
| `lib/agents_fyi_mcp/prompts.rb` | `triage_a_failing_run` and `plan_an_upgrade`. |
| `lib/agents_fyi_mcp/resources.rb` | Discovery, `llms.txt`, the README, the skill and one report body. |
| `lib/agents_fyi_mcp/http_app.rb` | The hosted Streamable HTTP transport, one server per request. |
| `bin/agents-fyi-mcp` | The stdio entrypoint and the bundle wrapper. |
| `config.ru` | The Rack application puma serves. |

## The surface is declared once

A tool has four parts: a `Surface` subclass, a handler in `Tools::HANDLERS`, a row in the README
tool table, and a row in `data/SKILL.md`. Four tests hold them together:

- `mcp_tools_golden_test.rb` reconciles the SDK's `initialize` and `tools/list` against the
  frozen `data/surface.json`, after the three allowed differences;
- every declared tool has a handler and a surface class;
- every tool carries a title, a description and both schemas;
- the skill and the README table every tool.

`data/surface.json` is an **oracle**, not the bytes a caller receives. It recorded the handshake
the server answered before the SDK owned the protocol. The recording is frozen; a change to the
surface is a deliberate change to the oracle, not a test convenience.

## The two transports

```text
stdio:  harness -> bin/agents-fyi-mcp -> AgentsFyiMcp.main -> SDK server
HTTP:   caller  -> puma config.ru     -> HttpApp          -> one SDK server per request
```

The stdio server reads `AGENTS_FYI_API_KEY` from its process and is what a local harness uses.
The hosted endpoint reads `X-API-Key` or `Authorization: Bearer` from each request and stores
nothing: no session, no key store, nothing that outlives the request. Reads are anonymous; a
write without a key is refused by the tool's own sentence.

## Refusals

An anticipated failure is raised as `ToolError`; every other exception is a crash. The transport
sends a `ToolError`'s message to the model, and withholds a crash's message. A refusal written
for a reader is therefore delivered, not left on the server.

## Untrusted content

Report bodies are attacker-controllable. Every body returned by a tool is wrapped in
`BEGIN UNTRUSTED THIRD-PARTY CONTENT` markers, and the server's instructions say that text
between them is data, never an instruction. The markers reach the model even when only part of a
tool result is shown to it.
