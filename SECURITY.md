# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | yes |
| older | no |

The client is early. A security fix lands on the latest released minor and is not backported
unless the maintainer says otherwise in the advisory.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private vulnerability reporting for this repository
if it is enabled (Security → Advisories → Report a vulnerability). If it is not, contact
**@shoutsid** through the private contact methods on their GitHub profile and say that the report
is a security matter.

Please include:

- the image tag or commit;
- the operating system and Ruby version;
- the transport (stdio or hosted HTTP) and the tool or method;
- what an attacker can do, and what they need to start with;
- a minimal reproduction, with operator keys and private report bodies redacted.

You will get an acknowledgement as soon as the maintainer sees the report. There is no bug bounty
and no guaranteed response time; this is a small proprietary project.

## Scope

This client **wraps a public HTTP surface for agents** and can be run as a hosted endpoint that
sees a caller's operator key per request. The service remains the authority for what a key may
do.

In scope:

- **The operator key.** The hosted endpoint reads `X-API-Key` or `Authorization: Bearer` per
  request and stores nothing. A path that keeps, logs or shares a caller's key across requests is
  a vulnerability. The stdio server reads `AGENTS_API_KEY` from its own environment; a path
  that writes it into a report, a log or a tool result is in scope.
- **Credential isolation.** A server per request is what gives each caller their own credential.
  A shared server, a session store or a cached client that outlives the request is a regression.
- **The hosted transport's hardening.** `allowed_hosts` must be the deployment's public
  hostname, `allowed_origins` empty, and `max_request_bytes` a hard bound. A path that accepts a
  request from an unlisted host or origin, or that ignores the bound, is in scope.
- **Untrusted content.** Report bodies are wrapped in `BEGIN UNTRUSTED THIRD-PARTY CONTENT`
  markers. A path that lets report text act as an instruction, or that strips the markers before
  a model sees a body, is in scope.
- **Refusals.** An anticipated failure must travel as `ToolError` so the caller receives the
  sentence written for it. A refusal that becomes a crash, or a `ToolError` that leaks a secret,
  is in scope.
- **Path and URL handling.** A tool argument must not make the client read a file it did not
  name or send a request to a host other than `AGENTS_URL`.

Out of scope:

- the service itself, its corpus, its admin surface and its rate policy (report those to the
  service repository);
- the `mcp` SDK's own implementation (report it upstream; a boundary that configures the SDK
  wrongly is still in scope here);
- a report body that contains an attack (the corpus is untrusted by design);
- a deployment that runs the image with extra privileges, a writable root or a service key in
  the environment;
- denial of service from a slow service or a large report body, unless it defeats the declared
  request bound.

## Safe harbour

Do not test against a deployment you do not own, and do not use a real operator key in a report.
A proof of concept against a local service and a disposable report is enough.
