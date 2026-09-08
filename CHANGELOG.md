# Changelog

## 2026-09-08

- Consolidated shared environment loading, array membership, and missing-variable collection in `lib/common.sh`. Report generation, upload, retention, and monitoring behavior remain unchanged.
- Added mocked coverage for shared environment-loading failures and archive dry-run collision handling. `./check` now includes the shared library.
