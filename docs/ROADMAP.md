# Roadmap

Planned features for `cloudflare-warp-action`.

Community votes and contributions are welcome - [open an issue](https://github.com/NX1X/cloudflare-warp-action/issues/new) or PR.

---

## Planned

- [ ] **macOS runner support** - install WARP via the official `.pkg` and adapt the MDM file format (macOS uses `/Library/Managed Preferences/com.cloudflare.warp.plist`)
- [ ] **ARM64 runner support** - verify the `cloudflare-warp` apt package on `linux/arm64` runners
- [ ] **Self-hosted runner hardening guide** - dedicated GUIDE.md section covering MDM file rotation, daemon hardening, and post-job cleanup verification
- [ ] **Pinned WARP version input** - `warp-version` input to install a specific package version (currently always installs latest)
- [ ] **Custom DNS resolver** - `dns-mode` and `dns-families` inputs to pin DoH resolver and family-protection settings
- [ ] **Output: registered device ID** - surface the (non-secret) device ID as an output for use in audit logs / SIEM
- [ ] **Reconnect-on-failure helper** - built-in retry on transient daemon errors mid-job (e.g. WARP edge maintenance)
- [ ] **Audit hook input** - optional webhook/SIEM URL the action POSTs to with connection events (zero-PII, opt-in)
- [ ] **Mutual TLS support** - for orgs that pair Service Auth with mTLS

---

## Completed

- [x] Install `cloudflare-warp` from Cloudflare's apt repository
- [x] Headless service-token enrollment via MDM XML at `/var/lib/cloudflare-warp/mdm.xml`
- [x] Connection mode selection (`warp`, `proxy`, `doh`, `warp+doh`)
- [x] Split-tunnel exclude / include routes (mutually exclusive)
- [x] Auto-detect new `tunnel ip add` vs legacy `add-excluded-route`/`add-included-route` syntax
- [x] Connection verification with retry (`test-connection`, `retry-count`, `retry-delay`)
- [x] Optional end-to-end ping test against an internal `test-host`
- [x] Outputs: `warp-version`, `connection-status`, `warp-ip`
- [x] Cleanup sub-action (disconnect, delete registration, remove MDM file)
- [x] Optional package removal in cleanup (`remove-warp: 'true'`)
- [x] State file at `~/.cloudflare-warp-state` for cleanup coordination (no credentials)
- [x] Manual release workflow with version validation, duplicate-tag check, floating major tag
- [x] CI workflow with pinned `actionlint` (v1.7.7) + `shellcheck` + structural validation
- [x] Unit test workflow with mock `warp-cli` (12 test groups)
- [x] Manual integration test workflow against a real Zero Trust org
