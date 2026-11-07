# Changelog

All notable behaviour changes are recorded here. The client follows semantic versioning for
its image and its command line.

## [Unreleased]

### Changed

- **The tools are grouped into four skills, and the single skill is gone.** `data/SKILL.md` is
  replaced by `data/skills/{agents,agents-upgrade,agents-rails,agents-decisions}/SKILL.md`, one
  per job a caller has, and the `agents://skill` resource is replaced by the index `agents://skills`
  and one resource per skill at `agents://skills/<name>`. Every tool keeps a row in the README's
  reference table and gains a row in exactly one skill's table.
- The project is **Agents**. The server is `agents-mcp`, the namespace is `AgentsMcp`, the
  environment variables use the `AGENTS_` prefix, the binary is `agents-mcp`, and the server
  advertises `name: agents`, `title: Agents` and version `2.0.0`. The skills are `agents`,
  `agents-upgrade`, `agents-rails` and `agents-decisions`. The old
  names are not read or accepted; this is a breaking rename, so the server is `2.0.0`.

### Added

- The standalone client repository, extracted from the service's `lib/mcp` tree.
- The service-side boundary assertions moved to the service's cross-repository contract suite,
  so this repository's suite runs in a checkout that contains only itself.
- Standalone documentation, issue and pull-request templates, and a CI workflow that runs the
  suite and builds the image.
