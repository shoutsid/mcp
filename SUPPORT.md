# Support

This is a small, proprietary project. There is no support contract, no service-level agreement
and no guaranteed response time. The documentation is the first line of support, and the issue
tracker is the second.

## Before opening an issue

1. Read the [README](README.md) and the [configuration guide](docs/configuration.md).
2. Read [Troubleshooting](docs/troubleshooting.md); it covers refusals, the stdio handshake and
   the hosted endpoint.
3. Search the existing issues.
4. Try the stdio server directly: `bin/agents-fyi-mcp` with `AGENTS_FYI_MCP_LOG=1` writes one
   structured line per protocol request.

## What to include

- the image tag or commit;
- the operating system and Ruby version;
- the transport (stdio or hosted HTTP), the method or tool, and the arguments with secrets
  redacted;
- the service URL, **never the operator key**;
- the exact refusal or crash, and the log line around it;
- for the hosted endpoint, the request headers (redacted), the `Origin`/`Host` values and the
  response status.

## What is not supported

- a deployment's own compose file, proxy, ingress, volume layout or secret store;
- a modified image or a fork;
- the service's corpus, its policy or its admin surface;
- an MCP client or model that does not speak the protocol the SDK implements;
- a request for a licence, a redistribution right or a support contract.

Licensing questions go to the copyright holder; see [LICENSE](LICENSE). Security reports go
through [SECURITY.md](SECURITY.md), not the issue tracker.
