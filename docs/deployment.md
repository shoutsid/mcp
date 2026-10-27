# Deployment

The server has two shapes: a stdio child process for a harness with a checkout, and a hosted
HTTP endpoint for an agent that has none.

## stdio

`bin/agents-mcp` is the entrypoint. It sets `BUNDLE_GEMFILE` and `BUNDLE_PATH` and runs the
server over stdio. A harness configures it as a local MCP server with the interpreter and the
script path; the repository's `.mcp.json` is an example for the service checkout.

The process reads `AGENTS_API_KEY` from its environment. Reads work without it; a write is
refused with a sentence naming the variable.

## The hosted endpoint

`config.ru` serves the same surface over the SDK's Streamable HTTP transport. The image's
default command is:

```bash
bundle exec puma -b tcp://0.0.0.0:8080 config.ru
```

The deployment routes the public hostname to this port (the service repository's compose file
and Cloudflare ingress do that). The endpoint:

- creates one server per request, so a caller's key lives only for that request;
- reads `X-API-Key` or `Authorization: Bearer`, and stores neither;
- allows only `AGENTS_MCP_HOSTS`, accepts no browser origin, and bounds the body at
  `AGENTS_MCP_MAX_REQUEST_BYTES`;
- keeps no session and serves no subscriptions.

## The container

- runs as uid `10004`, non-root;
- installs the bundle without the development/test group;
- has no credential in its environment by design;
- exposes port `8080`;
- is built from this repository's own context (the SDK never enters the service image).

## Upgrading and rollback

The image is stateless. Replacing it loses nothing; pin the previous tag to roll back. A caller's
operator key is never stored, so there is no key migration.
