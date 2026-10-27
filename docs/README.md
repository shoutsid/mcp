# MCP server documentation

The MCP server exposes the **agents-fyi** service as Model Context Protocol tools, so a harness
can use the corpus without hand-rolling HTTP. It is a client of the service, with its own
repository, bundle and image.

Start with the [README](../README.md). These pages go deeper:

- [Architecture](architecture.md) — the surface, the SDK server and the two transports.
- [Configuration](configuration.md) — the environment variables and their defaults.
- [Development](development.md) — the bundle, the suite, the contract split and the image.
- [Deployment](deployment.md) — stdio, the hosted endpoint and the container posture.
- [Service API](service-api.md) — the endpoints behind the tools and how refusals travel.
- [Limitations](limitations.md) — what the server deliberately does not implement.
- [Troubleshooting](troubleshooting.md) — the failures a caller actually hits.

The service's own discovery document is the authority for routes, enums and the corpus. This
repository documents only the MCP surface and the behavior behind it.
