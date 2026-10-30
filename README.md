# Agents MCP server

`bin/agents-mcp` exposes the service as MCP tools, so a harness can use it without
hand-rolling HTTP. It is what most callers actually touch: the `SKILL.md` a harness
installs is the same server explained to an agent as *when* to reach for a tool, and this
file is the reference behind it.

The protocol is the official Ruby SDK (`mcp` 1.8). The handshake, the tool list, the call,
pagination, cancellation and both transports are the gem's; what is here is the surface —
what a tool is called and what it says — and the behaviour behind it. `lib/agents_mcp/surface.rb`
declares the thirty-four `MCP::Tool` subclasses, `lib/agents_mcp/tools/` implements what they do,
and `data/surface.json` is the frozen recording the declared surface is reconciled against
(`test/mcp_tools_golden_test.rb`). The recording is no longer the bytes a client receives: a
server that serves a recorded handshake is reproducing one answer to the protocol rather than
implementing it, and every capability the SDK negotiates would be a lie the recording does not
tell.

| Tool | Purpose |
|---|---|
| `check_lockfile_ruby_compatibility` | Checks every gem a `Gemfile.lock` pins against the Ruby version you are moving to. The lockfile is read to answer and never stored; unknowns are counted separately, never passed |
| `check_ruby_compatibility` | Whether one gem release runs on the Ruby version you are moving to, from the release's declared requirement — `unknown` is never a pass |
| `record_release_facts` | The miner's write: the Ruby requirement each gem release declares, recorded against the release |
| `check_upgrade` | What breaks on the way from one release to another — asked *before* the failure |
| `find_answer` | What to do about a failure, and how much to trust it |
| `find_rails_edits` | The call sites in your own files for a Rails upgrade: the whole-word renames applied, everything else listed with the reason and not rewritten |
| `scan_upgrade_delta` | The same scan over only the files that moved since your manifest: added, changed, unchanged, deleted and skipped, with the edits they carry |
| `gem_migrations` | Which of your gems a machine may move without reading your code — a dead source, a fork for a release that shipped — and which need a decision |
| `precheck_report` | Ask whether a draft is already recorded, before filing it |
| `triage_failures` | A whole run of failures, each with a decision |
| `search_reports` | Find reports by symptom, error text or symbol |
| `get_release` | What one release changed, grouped by the change: a change with three reports is one finding with three witnesses |
| `get_report` | Fetch one report, with every fix proposed for it |
| `get_scenario` | One executable claim with the runs recorded against it: `runs: none` is a proposal, `unreached` counts for nothing |
| `claim_report` | Say you are solving an unsolved problem, so nobody repeats it |
| `release_report` | Give a claim back when you are not going to finish it |
| `record_outcome` | Say whether the fix worked, naming it if there are several |
| `propose_resolution` | Record the fix for a problem that had none |
| `rails_ladder` | Which Rails releases the ladder knows: where it starts, where it tops out, and each step's Ruby floor and how much of it a machine may apply |
| `rails_upgrade_plan` | The ordered steps of a Rails upgrade from 3.2 to now, each with the changes Rails' own guide documents and the changes this corpus executed |
| `plan_gem_moves` | What each gem a `Gemfile.lock` pins needs before a Rails move: keep, move to a recorded release, replace/remove, blocked, or unknown — and an unknown is not a pass |
| `list_upgrade_targets` | Which Rails applications this service is walking forward, best first, with the reasons for each one's place and what happened when it was tried — the corpus's own upgrade work, not a lookup |
| `list_decisions` | The blocks an upgrade walk is waiting on: the stage, the change, the evidence and the options, newest first |
| `get_decision` | One block in full: the context, evidence, typed options, proposals, accepted answer and the runs that carried its effects |
| `get_project_profile` | A project's upgrade profile, the service's verdict on whether it is walkable, its pending proposals and its consultant policy |
| `propose_decision` | Propose an answer with typed effects and provenance. Nothing is applied; a person accepts in the site admin or the project's portal |
| `create_decision` | Record an advisory question for a person when the walk did not ask about something; it never blocks a target and is not an effect |
| `propose_profile` | Suggest a profile field with the file that proves it; a person accepts the fields they believe |
| `withdraw_decision` | Take back your own proposal before it is accepted; an accepted answer is superseded, not withdrawn |
| `resolution_plan` | What the walk would do about each change in a project's move: the answer or rule in force, reports, open questions and what is missing |
| `verify_report` | Confirm or refute that the problem is real |
| `flag_report` | Object to a report that is wrong, or aimed at the reader |
| `submit_report` | Contribute a finding |
| `submit_reports` | Contribute a whole run of findings at once |

The decision tools are the agent's half of a blocked walk: `list_decisions` and
`get_decision` read the question, `propose_decision` records a typed proposal and
`withdraw_decision` takes one back, and `resolution_plan` says which answer, rule or
report is already in force for each change. There is deliberately no accept tool —
a person accepts in the site admin or the project's portal, because an agent that
could accept its own proposal would have made the operator's act a formality.

Both submission tools take `subject_kind`, and `search_reports` filters on it —
so a harness can file a platform limit or a harness quirk and find it again,
without a package being named anywhere in it.

Every tool carries MCP **annotations**, because a harness uses them to decide
whether a call needs its operator's permission: the read-only tools are
declared `readOnlyHint`, the writes are not, and none claim `destructiveHint` — the worst a
single call does is add a row. `claim_report` and `release_report` are the upsert
shape too: a second claim renews the one row rather than adding a second, so
repeating it cannot compound. `submit_report` and `submit_reports` are
deliberately *not* marked `idempotentHint`: a repeat is refused as a duplicate,
and a harness retrying on that hint would get a 409 it did not expect.
`flag_report` is there so an agent can act on a report that is wrong or that tries
to instruct it — from the surface agents actually use, rather than only over HTTP.



`search_reports` takes `published_after`: keep only reports whose release was
published on or after that date, which is how a model asks what changed after its
training data ends. It **excludes** reports with no recorded release date rather
than assuming they are recent, so an empty result means "nothing in the corpus is
known to be that new" rather than "nothing was released". The same filter is
`?published_after=` on `/api/reports/search`.

Every one of them takes a `trace` argument, and for `find_answer`,
`precheck_report`, `triage_failures`, `submit_report` and `submit_reports` that
argument can be the *only* one: a harness holding a traceback gets the answer, the
duplicate check, or the write done without composing prose first.
`triage_failures` and `submit_reports` take a list of them, so the shape of a
failing run is the shape of its argument — and both take the run's `library` once,
because a traceback from application code names no package to be scoped to. The
pair is the loop: triage says which of the run are new, `submit_reports` files
them and says which were new after all.

```bash
# The client has its own bundle (`mcp`, `rack`, `puma`); the application's does not carry it.
BUNDLE_PATH=~/.cache/agents-mcp/bundle bundle install   # once
AGENTS_API_KEY=afy_… bin/agents-mcp                 # stdio transport
                                       # or: ruby bin/agents-mcp
                                       # (`./scripts/dev.sh mcp` runs the suite from the service checkout)
```

The suite is this client's own, with no service behind it:

```sh
bundle exec ruby -Ilib -Itest test/all_test.rb
```

The wrapper sets `BUNDLE_GEMFILE` to this repository's Gemfile and `BUNDLE_PATH` to
`~/.cache/agents-mcp/bundle` (or `AGENTS_MCP_BUNDLE`), because two of the three callers —
the service checkout's `.mcp.json` and the generated `opencode` config — launch a command array
with no shell, and a single script path is the one thing all three can name. `agents_mcp.rb`
at this repository's root still exists and loads the wrapper: `/.well-known/agents.json`
names that path as this service's MCP server, and a documented command that stopped working
would be a lie in the document whose job is to describe the surface.

The server sends session-level `instructions` that carry the workflow and the untrusted-content
rule, so the warning reaches the model even when only part of a tool result is
shown to it; every report body is also wrapped in `BEGIN UNTRUSTED THIRD-PARTY
CONTENT` markers, because report text is attacker-controllable and an agent that
followed instructions found inside one would be the payload of a prompt-injection
attack.
The service checkout's `.mcp.json` registers it for harnesses that read that file, and the
service's `.claude/skills/agents/SKILL.md` teaches an agent *when* to reach for it. This
repository ships the same text as `data/SKILL.md`, so a harness that installs the client has the
skill without needing the service checkout.

## Prompts and resources

The recording advertised `prompts` and `resources` capabilities and the old server answered
nothing with them. They now mean something, in the direction of keeping the promise rather than
the opposite:

- **`prompts/list`** carries `triage_a_failing_run` and `plan_an_upgrade` — the two workflows the
  instructions describe, laid out as steps. A prompt changes nothing; the tools it names still
  decide and still refuse.
- **`resources/list`** carries `agents://discovery` and `agents://llms.txt` (fetched live
  from the service), `agents://readme` and `agents://skill` (the files this component
  ships), and the template `report://{id}` for one report's whole body without a tool call.

The version a client is offered is still the recording's: `tools`, `prompts` and `resources` with
`listChanged: false`, and no `logging` capability, because this server never changes a list and does
not implement `log/setLevel`. A capability that promises more than the server does is a lie in the
direction that matters.

## The hosted endpoint

`config.ru` serves the same surface over the SDK's Streamable HTTP transport, as a service of its
own in the service's compose file (`mcp`). It builds one server per request, so the caller's own operator
key — `X-API-Key: afy_…` or `Authorization: Bearer afy_…` — is read per request and stored nowhere:
reads are anonymous, and a write without a key is refused by the same rule the stdio server
applies — with the sentence that names the header *this* caller can set, not the environment
variable the stdio server reads, because a remote caller cannot reach that variable. The
SDK's DNS-rebinding protection names the public hostname, origins are empty (no browser is meant to
call it), and `max_request_bytes` is a hard bound. The harness probe keeps using stdio, because a
probe measures the surface a local harness reaches; the endpoint is for agents that have no
checkout.

**A failure the tool anticipated is raised as `ToolError`, and that is a contract
with the transport rather than a style choice.** The transport sends a `ToolError`'s
message to the model; any other exception is a *crash*, and the model receives
only `Error executing tool <name>` while the text stays on the server. Every
refusal here is written for a caller to act on — register a key, send `q` instead
of `query`, this reads forward moves — and all of them were being discarded, which
is how a model asked for a backwards upgrade, was told `Error executing tool
check_upgrade`, and reported a session fault to its user. `_fail` is the one place
that raises, so a new refusal cannot be added as a bare `RuntimeError` by accident.

The tool layer is tested without a deployment — HTTP is stubbed, so a broken
tool cannot pass by reaching a live service by accident (`test`). One file
goes the other way and drives the server over the real stdio transport, with a
protocol handshake and no HTTP at all: a tool that works in-process can still be
unreachable from a harness, and only `mcp_transport_test.rb` would notice. It also
reads every tool's schema and annotations off the wire, so the arguments a model
is offered cannot drift from the arguments the function accepts.

Two of the SDK boundary's traps have tests of their own, because neither is visible from a
string-keyed in-process call. `mcp_transport_test.rb` drives a tool through the shape a transport
actually delivers — `JSON.parse(..., symbolize_names: true)`, symbol keys at every level including
inside arrays — and `Context` is the one adapter that converts them back. The same file asserts that
a `ToolError` is *returned* as `isError: true` rather than raised, because the SDK withholds a
raised exception's message and the model would receive `Error executing tool <name>` with the
sentence left on the server. `mcp_boundary_test.rb` asserts the other direction: no `mcp` gem in the
service's `Gemfile.lock`, no `package.yml` here, and the component still named in `.dockerignore`.

## Does a model actually reach the tools?

Both of those suites call the tools. Neither says whether an *agent* finds them:
a tool can answer perfectly and be undiscoverable, or discoverable and unusable by
a model that has to choose it from a list. From the service checkout,
`scripts/harness-probe.rb` runs that half — `opencode` with a generated config that
mounts this server through Code Mode and denies every other capability — against a
task suite, with a small model, and scores the run without a judge model:

```bash
./scripts/harness-probe.rb                 # 6 tasks × 3 attempts, exit 1 on any flake
./scripts/harness-probe.rb --repeat 1      # one pass
./scripts/harness-probe.rb --only unknown_library_is_not_answered --verbose
```

See the service's `components/harness/README.md` (in the service checkout) for what it checks before it measures
anything, why the score is "passed every repeat" rather than a pass rate, and how
the free and paid routes of the default model relate.

## Documentation

- [Documentation index](docs/README.md) — every page below, with a one-line purpose.
- [Architecture](docs/architecture.md) — the surface, the SDK server and the two transports.
- [Configuration](docs/configuration.md) — the environment variables and their defaults.
- [Development](docs/development.md) — the bundle, the suite, the contract split and the image.
- [Deployment](docs/deployment.md) — stdio, the hosted endpoint and the container posture.
- [Service API](docs/service-api.md) — the endpoints behind the tools and how refusals travel.
- [Limitations](docs/limitations.md) — what the server deliberately does not implement.
- [Troubleshooting](docs/troubleshooting.md) — the failures a caller actually hits.
- [Changelog](CHANGELOG.md).

## Development

```bash
bundle install
bundle exec ruby -Ilib -Itest test/all_test.rb
```

The suite needs no network and no service: the HTTP layer is stubbed, and one file opens a real
stdio session with the server. The client's agreements with the service — the service lockfile,
its `.dockerignore`, its canonical skill — live in the service's own contract suite, because only
a checkout that holds both sides can test them. See [Development](docs/development.md).

## Contributing

This is a proprietary repository. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an
issue or a pull request; contributions are accepted only by prior arrangement. Security reports
go through [SECURITY.md](SECURITY.md), not a public issue.

## License

Copyright (c) 2026 James Summerill. All rights reserved. No use, copying, modification,
publication, distribution, sublicensing or sale is permitted without prior written permission
from the copyright holder. See [LICENSE](LICENSE).
