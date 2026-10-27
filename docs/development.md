# Development

Ruby 3.3.12 is the interpreter the image pins and `.ruby-version` names. The server has its own
bundle; the service's bundle deliberately does not carry `mcp`.

## The suite

```bash
git clone git@github.com:shoutsid/mcp.git
cd mcp
bundle install
bundle exec ruby -Ilib -Itest test/all_test.rb
```

One file:

```bash
bundle exec ruby -Ilib -Itest test/mcp_tools_golden_test.rb
```

The HTTP layer is stubbed, so no deployment is needed. `mcp_transport_test.rb` opens a real
stdio session with the server and reads every tool's schema and annotations off the wire; that
is the half an in-process call cannot prove.

## The contract split

This repository proves what the client does with its own artifacts. The agreements that need
both repositories live in the service's `test/contracts/mcp/` suite:

- the service's `Gemfile.lock` carries no `mcp` gem;
- the service's `.dockerignore` keeps all four clients out of the image;
- `lib/mcp` is not a package;
- `data/SKILL.md` is byte-identical to the service's canonical `.claude/skills/agents/SKILL.md`.

Do not copy the service's lockfile, `.dockerignore` or canonical skill into this repository. If
a change needs both sides to test, add it to the service's contract suite.

## The image

```bash
docker build -t agents-mcp .
docker run --rm --entrypoint id agents-mcp -un   # expect mcp
```

The image runs as uid `10004`, has no credential in its environment, and serves the hosted
endpoint with puma from `config.ru`.

## Style

The service's RuboCop run scans this tree when it is checked out as a submodule. In standalone
CI the checks are `ruby -c` over every Ruby file, the suite, and the image build.

- Two-space indentation, frozen string literals, no trailing whitespace.
- Comments explain **why**, not what the code already says.
- Errors say what the caller should do next, in one sentence, with the count or the limit named.
- Tests are named as sentences, and a test that documents a deliberate refusal says so.
