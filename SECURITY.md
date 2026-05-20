# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| latest  | :white_check_mark: |
| < latest| :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, please report vulnerabilities privately:

1. Go to the [Security Advisories](https://github.com/NX1X/cloudflare-warp-action/security/advisories) page
2. Click "Report a vulnerability"
3. Provide a clear description and reproduction steps

You will receive a response within 72 hours. If confirmed, a fix will be
released as a patch version and credited in the changelog.

## Security Practices

- CI runs `actionlint` and `shellcheck` on every push and PR
- All secrets are passed through `env:` blocks (masked by GitHub Actions) - never inlined in shell commands
- The MDM file at `/var/lib/cloudflare-warp/mdm.xml` (which contains the service token credentials) is created with `chmod 600` owned by `root:root` - readable only by the WARP daemon
- The MDM file is written via `mktemp` + `install` rather than `sudo tee`, so the service token never appears on a sudo command line (visible in `/proc/<pid>/cmdline`)
- The verify step redacts all `<string>` values from the MDM file in CI output using `sed`
- The registration-show output redacts Device ID, Account ID, Public Key, and Token via `sed`
- The state file (`~/.cloudflare-warp-state`) contains only paths and flags - no credentials
- The cleanup sub-action removes the MDM file as the primary defense against credentials persisting on self-hosted runners
- No telemetry, no analytics, no external calls beyond Cloudflare itself - all processing stays on your runner
- Dependencies are monitored via Dependabot for GitHub Actions version updates
- Releases include source verification via git tags
- `softprops/action-gh-release` (used in the release workflow) is pinned to a commit SHA to prevent supply chain attacks
- All workflows declare explicit least-privilege `permissions:` blocks

## Threat Model Notes

- WARP gives the runner network-level access to your Zero Trust network. Use `include-routes` to limit scope to only the CIDRs you actually need to reach.
- Service tokens for device enrollment should be scoped to the minimum required Device Enrollment policy in Cloudflare Zero Trust. Do not share the same token across unrelated workflows.
- Rotate service tokens at least once per year (the maximum Cloudflare allows). Update GitHub Secrets immediately on rotation.
- On self-hosted runners, always run the cleanup sub-action with `if: always()` so the MDM file is removed even if the job fails.

## Security Changelog

| Date | Change |
|------|--------|
| 2026-05-09 | v1.0.0 - Initial release with `chmod 600` MDM file (root-only), MDM written via `mktemp` to avoid sudo cmdline exposure, secret redaction in verify and registration-show output, cleanup sub-action removes MDM file, state file contains no credentials |
