# Public Release Checklist

Complete this checklist before the first public GitHub push and before every
release that changes third-party components.

## Copyright and Licensing

- [x] Root MIT license exists.
- [x] Project-owned exporter declares MIT.
- [x] Third-party component inventory and distribution boundaries are recorded.
- [x] No third-party source code, dashboard JSON, logos, screenshots, fonts, or
      binary artifacts are included; dashboard and alert assets are original.
- [x] Re-check all upstream licenses and version pins immediately before release.
- [ ] If any dependency is vendored or modified, add its complete license,
      notices, and required source/distribution materials.

## Name and Trademarks

- [x] Basic public web/GitHub search found no obvious monitoring/software project
      using the exact `OpsPika` name.
- [ ] Perform formal trademark clearance in intended countries/classes before a
      commercial launch.
- [ ] Check domain, package-registry, social-account, and organization-name
      availability before announcing the brand.
- [ ] Do not use third-party logos or imply affiliation.

## Repository Hygiene

- [x] Implementation tracking files are ignored.
- [x] Credentials, `.env`, authorization keys, backups, runtime data, and
      validation downloads are ignored.
- [x] Linux scripts are normalized to LF through `.gitattributes`.
- [x] Inspect `git status --short --ignored` before the first commit.
- [x] Scan the complete staged tree and existing history for high-confidence
      secrets before making the repository public.
- [x] Confirm no large or binary artifacts are staged.

## Validation

- [x] Bash syntax passes.
- [x] ShellCheck passes.
- [x] Node.js unit and syntax tests pass.
- [x] Pinned OpenTelemetry configurations validate.
- [x] Process exporter passed a disposable PM2 7 integration test.
- [x] Three original dashboards and seven alert templates pass asset validation.
- [x] Dashboards, log indexes, alerts, and all 21 panel queries passed against a
      clean disposable OpenObserve v0.90.3 server.
- [ ] Run the central and agent Ubuntu acceptance tests.
- [x] Clean-import dashboards and alerts into the pinned live OpenObserve version.

## Release Decision

This checklist reduces risk but is not legal advice or a substitute for counsel.
Copyright licensing and trademark clearance are separate reviews.
