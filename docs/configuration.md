# Configuration

The server reads its configuration from the environment. There is no config file.

## The service

| Variable | Default | Meaning |
|---|---|---|
| `AGENTS_FYI_URL` | `https://agents.shoutsid.fyi` | The service base URL. |
| `AGENTS_FYI_API_KEY` | empty | The operator key for the stdio server. Reads are anonymous; writes need it. |
| `AGENTS_FYI_TIMEOUT` | `25` | One HTTP call's open and read timeout, in seconds. |
| `AGENTS_FYI_RECORD` | on | Whether this server's reads count as demand. Set `false` for a self-check or a harness probe. |
| `AGENTS_FYI_MCP_LOG` | on | One structured JSON line per protocol request. Set `false` in the suite. |

## The hosted endpoint

| Variable | Default | Meaning |
|---|---|---|
| `AGENTS_FYI_MCP_HOSTS` | `agents.shoutsid.fyi` | Comma-separated `allowed_hosts` for the SDK's DNS-rebinding protection. |
| `AGENTS_FYI_MCP_ORIGINS` | empty | Comma-separated `allowed_origins`. Empty because no browser is meant to call it. |
| `AGENTS_FYI_MCP_MAX_REQUEST_BYTES` | `1048576` | The hard request bound, rather than the SDK's 4 MiB default. |

## The stdio wrapper

| Variable | Default | Meaning |
|---|---|---|
| `BUNDLE_GEMFILE` | this repository's `Gemfile` | Set by `bin/agents-fyi-mcp` if unset. |
| `BUNDLE_PATH` | `~/.cache/agents-fyi-mcp/bundle` | Set by the wrapper if unset. `AGENTS_FYI_MCP_BUNDLE` is the fallback the wrapper uses when `BUNDLE_PATH` is also unset. |

The hosted endpoint reads each caller's key, so it has no server-side key variable. A key in the
container's environment would hand every remote caller the authoring account.

## `.env.example`

The repository ships a template. Copy it to `.env` only for a local run; the image and the
compose deployment read the environment their orchestrator gives them.
