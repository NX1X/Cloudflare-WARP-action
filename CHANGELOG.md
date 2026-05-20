# Changelog

All notable changes to this action are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

## [1.0.0] - 2026-05-20

First public release. Status: **Beta** - the full pipeline has 304 unit-test assertions against a mocked `warp-cli`, but has not yet been validated end-to-end against a real Cloudflare Zero Trust organization. Pin to `@v1.0.0` (not `@v1`) until a stable release is cut.

Part of the NXTools Collection by NX1X (https://nx1xlab.dev/nxtools).

### Added
- Composite GitHub Action that installs `cloudflare-warp` from the official Cloudflare apt repository and enrolls the runner into a Zero Trust organization.
- Headless device enrollment via an MDM XML file at `/var/lib/cloudflare-warp/mdm.xml` using `auth_client_id` / `auth_client_secret` for service-token authentication (no browser, no `teams-enroll`).
- Connection-mode selection: `warp` (full tunnel), `proxy` (SOCKS5/HTTP), `doh` (DNS-only), `warp+doh`.
- Split-tunnel support: `exclude-routes` and `include-routes` (mutually exclusive, newline-separated CIDRs). Auto-detects new `tunnel ip add <CIDR> exclude|include` syntax with fallback to legacy `add-excluded-route` / `add-included-route`.
- Connection verification with retry logic (`test-connection`, `retry-count`, `retry-delay`) and optional end-to-end ping against an internal `test-host`.
- Outputs: `warp-version`, `connection-status` (`connected` / `failed` / `skipped`), `warp-ip`.
- Cleanup sub-action: disconnects WARP, deletes the device registration, removes the MDM file. Optional `remove-warp: 'true'` to uninstall the package as well.
- State file at `~/.cloudflare-warp-state` for cleanup coordination (paths and flags only - no credentials).
- `scripts/` directory containing every step of the pipeline as a standalone testable shell script (`scripts/01-validate-inputs.sh` ... `scripts/10-write-state.sh`, plus `scripts/set-skipped-status.sh`). Two sourceable libraries: `scripts/lib/validate.sh` (`validate_mode`, `validate_positive_int`, `validate_org`, `validate_cidr`, `check_routes`, `check_exclusivity`) and `scripts/lib/common.sh` (`trim`, `redact_strings`, `redact_registration`, `wait_for_daemon`, `wait_for_registration`). `cleanup/cleanup.sh` for the cleanup sub-action.
- `tests/` test harness with a configurable mock `warp-cli` (`tests/mock_warp_cli.sh`) driven by `DAEMON_READY_AFTER`, `REGISTERED_AFTER`, `FAIL_TUNNEL_NEW_SYNTAX`, `CONNECT_FAILS_FIRST`, `NEVER_CONNECTS`, `REGISTRATION_FAILS` knobs. 304 assertions across 14 test files covering:
  - Every validator (mode, retry int, org name, CIDR, route exclusivity).
  - MDM XML generation, redaction, XML-injection safety, and verification that `install` is invoked with `-m 600 -o root -g root`.
  - Daemon-readiness wait (success and timeout paths).
  - Registration timeout, registration-show redaction (Device ID / Account ID / Public Key / Token).
  - Split-tunnel new-syntax success and legacy-fallback paths.
  - Connection verify: success on first try, success on retry attempt N, never-connects timeout, ping success, ping failure, `connection-status=skipped`.
  - WARP IP capture: interface present, interface absent (mode=doh).
  - State file writing (no credentials).
  - Cleanup: happy path, missing state file, malformed state file, `warp-cli` not on PATH, `registration delete` falling back to `teams-unenroll`, `remove-warp=true`.
  - Install step (`scripts/02-install-warp.sh`): shimmed `lsb_release` / `curl` / `gpg` / `sudo` / `tee` / `apt-get` / `warp-cli`. Asserts the correct command sequence, distro codename interpolation, `signed-by` keyring path, `command -v lsb_release` early bail, `set -e` + `pipefail` aborting on `curl` failure, and `warp-version` written to `$GITHUB_OUTPUT` as a single `key=value` line with no heredoc framing.
  - Strict-mode flags: every main script enables `-e`, `-u`, and `pipefail`; `cleanup/cleanup.sh` intentionally omits `-e`. Includes a runtime canary proving `pipefail` aborts on pipe-head failure.
  - Missing-env behaviour: for each script that declares `: "${VAR:?}"` requirements, each var is dropped individually and the script must exit non-zero, name the variable, and (for the MDM step) NOT leave a half-baked file on disk.
  - End-to-end mocked pipeline run.
- CI workflow with pinned `actionlint` (v1.7.7) and `shellcheck` plus structural validation (required files, MDM keys present, secrets only in `env:` blocks, secret inputs never under `scripts/`, cleanup removes the MDM file).
- Unit-test workflow that runs `bash tests/run.sh` plus a dedicated shellcheck job over `scripts/`, `scripts/lib/`, `cleanup/cleanup.sh`, and `tests/`.
- Manual integration-test workflow (`workflow_dispatch`) against a real Zero Trust org, verifying outbound traffic via `cdn-cgi/trace`.
- Manual release workflow with version-format validation, duplicate-tag check, CHANGELOG-extracted release notes, and a floating major-version tag (`v1` -> latest `v1.x.x`).
- Documentation: `README.md` (quick start, inputs/outputs, split-tunnel and cleanup examples), `GUIDE.md` (Cloudflare org / service-token / GitHub-secrets walkthrough), `docs/HOW-IT-WORKS.md` (per-step rationale), `docs/ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.

### Security
- All `${{ inputs.* }}` and credential expressions in shell steps routed through `env:` blocks (never inlined). CI asserts this.
- Secret inputs (`auth-client-id` / `auth-client-secret`) MUST NOT appear anywhere under `scripts/`. CI asserts this.
- Input validation rejects malformed mode, retry counts, organization names, and CIDR ranges before any side-effecting work runs.
- MDM file written with `chmod 600` and `root:root` ownership (only the WARP daemon can read credentials at rest).
- MDM file written via `mktemp` + `install` rather than `sudo tee`, so service tokens never appear on a sudo command line (or in `/proc/<pid>/cmdline`).
- Required-env-var checks at the top of every secret-touching script ensure a missing credential causes a hard fail before any file write - no half-baked MDM file can land on disk.
- Verify step redacts every `<string>` value from MDM file output via `sed`.
- Registration-show output redacts Device ID, Account ID, Public Key, and Token via `sed`.
- State file contains only file paths and flags - no credentials at rest after cleanup.
- Cleanup sub-action removes the MDM file as the primary defense against credentials persisting on self-hosted runners between jobs.
- `softprops/action-gh-release` pinned to commit SHA to defend against supply-chain attacks.
- Explicit `permissions` blocks on all workflows (least-privilege `contents: read` everywhere except the release job).
- All typographic em dashes (U+2014) and en dashes (U+2013) across the repository normalised to regular hyphens (U+002D) for consistency.
