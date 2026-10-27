# Limitations

These are deliberate.

- **No sessions or subscriptions.** The hosted transport is stateless and builds one server per
  request. A client that needs server-initiated notifications should use the stdio server, where
  the connection carries them.
- **No `logging` capability and no `log/setLevel`.** The server does not promise a capability it
  does not implement. Its own request log is a structured line on the process's stderr/stdout,
  not an MCP logging surface.
- **No accept, apply or verify tool.** A person accepts in the site admin or the project's
  portal. An agent that could accept its own proposal would make the operator's act a formality.
- **Reads are anonymous; writes need a key.** A write without `AGENTS_API_KEY` (stdio) or a
  request header (hosted) is refused with the sentence that names the thing that caller can set.
- **The service is the authority.** A tool answers what the service answers. A 503, a paused
  collection or a refused proposal is reported as such, not retried into a different answer.
- **The corpus is untrusted.** Report text is wrapped in markers and is never an instruction.
  The server can put the markers around the body; it cannot make a model obey them.
- **The recording is not the live protocol.** `data/surface.json` is the frozen oracle the
  declared surface is reconciled against. The SDK answers the handshake; the recording is not
  replayed as bytes.
- **The hosted endpoint has no server-side key.** That is a feature, not a missing convenience:
  a key in the container would hand every remote caller the authoring account.
- **No provider or model is chosen here.** The server exposes tools; the harness's model decides
  when to call them.
- **The service must be reachable.** There is no local corpus, no cache and no offline mode.
