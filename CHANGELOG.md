# Changelog

All notable behaviour changes are recorded here. The client follows semantic versioning for
its image and its command line.

## [Unreleased]

### Added

- The standalone client repository, extracted from the service's `lib/mcp` tree.
- The service-side boundary assertions moved to the service's cross-repository contract suite,
  so this repository's suite runs in a checkout that contains only itself.
- Standalone documentation, issue and pull-request templates, and a CI workflow that runs the
  suite and builds the image.
