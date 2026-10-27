## Summary

<!-- One or two sentences: what does this change do, and why? -->

## Related issue

<!-- Link the issue this closes, or explain why there is none. -->

## What changed

<!--
  - the tool, schema, annotation, transport, environment variable or document that moved;
  - the files or components touched;
  - anything a reviewer should look at first.
-->

## How I tested it

<!--
  - the command(s) you ran;
  - the Ruby version, and whether a service or Docker was involved;
  - the new or updated test that would fail without this change.
-->

```bash
bundle exec ruby -Ilib -Itest test/all_test.rb
```

## Checklist

- [ ] I read [CONTRIBUTING.md](https://github.com/shoutsid/mcp/blob/main/CONTRIBUTING.md), and I understand this repository is proprietary and a pull request does not grant a licence.
- [ ] The change is one concern.
- [ ] A test would fail without this change.
- [ ] The suite passes locally: `bundle exec ruby -Ilib -Itest test/all_test.rb`.
- [ ] No new runtime dependency was added without prior discussion.
- [ ] A tool added, renamed or removed has a row in the README table and in `data/SKILL.md`.
- [ ] The docs are updated if a tool, annotation, schema, transport or environment variable changed.
- [ ] No secret, operator key or private report body is present in a fixture or this pull request.
- [ ] If the agreement needs the service's lockfile, `.dockerignore` or canonical skill, the test lives in the service's contract suite rather than being skipped here.
