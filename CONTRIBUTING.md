# Contributing

This repository is **proprietary**. It is public so operators and reviewers can read the
client, not because it is open source. See [LICENSE](LICENSE).

## Before you write code

Open an issue first and describe the change. Contributions are accepted only by prior
arrangement with the copyright holder. Do not send a pull request that adds a feature, a
dependency or a large refactor without that conversation; it may be declined for reasons that
have nothing to do with the quality of the code.

Opening an issue or a pull request does not grant a licence to use the repository, and does not
transfer ownership of your contribution. Any contribution that is accepted is subject to a
separate written agreement with the copyright holder.

## What is welcome

- A reproducible bug report with the command, the version, the operating system and a redacted
  log.
- A correction to documentation that is wrong about the current behaviour.
- A test that demonstrates a real failure, with the smallest reproduction you can find.
- A focused fix, discussed first.

## Development

You need Ruby 3.3.12 or newer, matching the image and `.ruby-version`.

```bash
git clone git@github.com:shoutsid/mcp.git
cd mcp
bundle install
bundle exec ruby -Ilib -Itest test/all_test.rb
```

A single file:

```bash
bundle exec ruby -Ilib -Itest test/mcp_tools_golden_test.rb
```

The suite needs no network and no service: the HTTP layer is stubbed, and one file opens a real
stdio session with the server. If a change needs the service's schema, its compose file or its
image context to test, it belongs in the service's cross-repository contract suite. See
[Development](docs/development.md) for the split.

The image:

```bash
docker build -t agentsfyi-mcp .
```

## Design rules

- **The SDK owns the protocol.** The gem answers the handshake, the tool list, calls,
  pagination, cancellation and both transports. This repository owns the surface and the
  behaviour behind it.
- **An anticipated failure is a `ToolError`.** Every other exception is a crash, and the model
  receives only `Error executing tool <name>` rather than the sentence written for it.
- **Every tool carries an annotation and both schemas.** Unset is not neutral: a harness reads
  the annotations to decide whether a call needs permission.
- **The service bundle must not carry `mcp`.** The client's bundle is its own, and the
  service's root lockfile is asserted not to carry the gem.
- **The skill and the README table every tool.** A tool that ships without a row in both is a
  tool a model cannot find.
- **Cross-repository agreements live in the service's contract suite.** Do not add a local copy
  of the service's lockfile, `.dockerignore` or canonical `.claude` skill.
- **Do not skip a test to make the suite green.** If an agreement needs both repositories, move
  it to the service's contract suite; if it can be stated here, state it here.

## Style

- Two-space indentation, frozen string literals, no trailing whitespace.
- Comments explain **why**, not what the code already says.
- Errors say what the caller should do next, in one sentence, with the count or the limit named.
- Tests are named as sentences, and a test that documents a deliberate refusal says so.

## Pull requests

- One concern per change.
- Add or update a test that would fail without the change.
- Update the README tool table and `data/SKILL.md` when a tool is added, renamed or removed.
- Do not add a secret, a token or a private report body to a fixture.
- Describe how you tested it, including the Ruby version and whether a service or Docker was
  involved.

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).

## Conduct

By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
