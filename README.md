# cloudflare-warp-action

[![Status: Beta](https://img.shields.io/badge/status-beta-yellow)](#)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Cloudflare%20WARP-blue?logo=github)](https://github.com/marketplace/actions/cloudflare-warp-setup)
[![Latest Release](https://img.shields.io/github/v/release/NX1X/cloudflare-warp-action?label=version&color=brightgreen)](https://github.com/NX1X/cloudflare-warp-action/releases/latest)
[![CI](https://github.com/NX1X/cloudflare-warp-action/actions/workflows/ci.yml/badge.svg)](https://github.com/NX1X/cloudflare-warp-action/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![NXTools](https://img.shields.io/badge/NXTools-Collection-orange)](https://nx1xlab.dev/nxtools)
![Views](https://komarev.com/ghpvc/?username=NX1X-cloudflare-warp-action&label=views&color=f66a0a)

> **Status: Beta (v1.0.0).** This is the first release. The full pipeline has 304 unit-test assertions against a mocked `warp-cli`, but it has not yet been validated end-to-end against a real Cloudflare Zero Trust organization. Inputs and outputs are intended to be stable from this version onward, but a fix surfaced by real-world testing may land in a subsequent patch (`1.0.1`, `1.0.2`, ...). Pin to the exact tag `@v1.0.0` rather than the floating `@v1` if you need a frozen interface, and report any issues at [github.com/NX1X/cloudflare-warp-action/issues](https://github.com/NX1X/cloudflare-warp-action/issues).

Install the **Cloudflare WARP** client on a GitHub Actions runner and enroll it into your Cloudflare Zero Trust organization. After this action runs, the runner has full network-level access to your internal resources - any tool (`ssh`, `curl`, `psql`, `kubectl`, `rsync`, etc.) reaches internal IPs and hostnames as if the runner were on your corporate network.

Part of the [NXTools Collection](https://nx1xlab.dev/nxtools) by [NX1X](https://github.com/NX1X).

---

## Quick Start

```yaml
steps:
  - uses: NX1X/cloudflare-warp-action@v1
    with:
      organization:        ${{ secrets.CF_WARP_ORG }}
      auth-client-id:      ${{ secrets.CF_WARP_CLIENT_ID }}
      auth-client-secret:  ${{ secrets.CF_WARP_CLIENT_SECRET }}

  # The runner is now on your corporate network
  - run: ssh admin@10.0.1.50 "docker compose up -d"
  - run: psql -h db.internal.corp -U deploy -c "SELECT 1"
  - run: curl -sf http://api.internal.corp/health
  - run: kubectl --server=https://k8s.internal.corp:6443 get pods
```

New to this? See the **[Setup Guide](GUIDE.md)** for a walkthrough of the Cloudflare Zero Trust setup, service token creation, and GitHub secrets.

---

## How It Differs From the Tunnel Actions

| | Tunnel actions (SSH, TCP) | **WARP action** |
|---|---|---|
| **Scope** | Per-service (one host/port per config) | Full network (entire corporate network) |
| **Mechanism** | `cloudflared access` ProxyCommand | WARP VPN client (TUN interface) |
| **Auth** | Service token per Cloudflare Access app | Device enrollment via Zero Trust org |
| **Use when** | You need 1-3 specific services | You need many internal services |
| **Attack surface** | Minimal (only configured hosts) | Broad (all routable internal IPs) |

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `organization` | **yes** | - | Cloudflare Zero Trust team name (the subdomain in `https://<team>.cloudflareaccess.com`) |
| `auth-client-id` | **yes** | - | Service token Client ID for headless device enrollment |
| `auth-client-secret` | **yes** | - | Service token Client Secret for headless device enrollment |
| `mode` | no | `warp` | Connection mode: `warp` (full tunnel), `proxy` (SOCKS5/HTTP proxy), `doh` (DNS-only), `warp+doh` |
| `exclude-routes` | no | `''` | CIDR ranges to exclude from the WARP tunnel (one per line). Mutually exclusive with `include-routes`. |
| `include-routes` | no | `''` | CIDR ranges to include in the WARP tunnel (only these routed - everything else direct). Mutually exclusive with `exclude-routes`. |
| `test-connection` | no | `true` | Verify WARP is connected after setup |
| `test-host` | no | `''` | Internal hostname or IP to ping for end-to-end verification |
| `retry-count` | no | `3` | Number of attempts when waiting for connection / pinging the test host |
| `retry-delay` | no | `5` | Seconds between retry attempts |

---

## Outputs

| Output | Description |
|--------|-------------|
| `warp-version` | Installed `cloudflare-warp` version (e.g. `2024.6.415`) |
| `connection-status` | `connected`, `failed`, or `skipped` |
| `warp-ip` | The runner's WARP tunnel IPv4 (e.g. `100.96.1.42`) - empty for `mode=doh` |

---

## Split Tunneling

**Exclude mode** - send everything through WARP except listed CIDRs (keep GitHub API direct):

```yaml
- uses: NX1X/cloudflare-warp-action@v1
  with:
    organization:       ${{ secrets.CF_WARP_ORG }}
    auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
    auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
    exclude-routes: |
      140.82.112.0/20
      143.55.64.0/20
```

**Include mode** - only send listed CIDRs through WARP, everything else direct (minimal blast radius):

```yaml
- uses: NX1X/cloudflare-warp-action@v1
  with:
    organization:       ${{ secrets.CF_WARP_ORG }}
    auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
    auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
    include-routes: |
      10.0.0.0/8
      172.16.0.0/12
```

---

## Verifying End-to-End Connectivity

Set `test-host` to an internal hostname or IP that your runner should be able to reach. The action pings it after WARP comes up and fails fast if routing isn't working:

```yaml
- uses: NX1X/cloudflare-warp-action@v1
  with:
    organization:       ${{ secrets.CF_WARP_ORG }}
    auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
    auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
    test-host:          db.internal.corp
    retry-count:        '5'
    retry-delay:        '10'
```

---

## Cleanup

Disconnect WARP, delete the device registration, and remove the MDM file (which contains the service token credentials):

```yaml
- uses: NX1X/cloudflare-warp-action/cleanup@v1
  if: always()
```

Optional: also uninstall the `cloudflare-warp` package:

```yaml
- uses: NX1X/cloudflare-warp-action/cleanup@v1
  if: always()
  with:
    remove-warp: 'true'
```

> **Self-hosted runners:** always run cleanup. The MDM file at `/var/lib/cloudflare-warp/mdm.xml` contains your service token credentials and persists across jobs unless removed.

---

## Supported Runners

Ubuntu/Debian only (the `cloudflare-warp` package is `.deb`):

- `ubuntu-latest` (Ubuntu 24.04)
- `ubuntu-22.04`
- `ubuntu-20.04`

---

## Documentation

- **[Setup Guide](GUIDE.md)** - Cloudflare Zero Trust org setup, service token creation, GitHub secrets, real workflows
- **[How It Works](docs/HOW-IT-WORKS.md)** - step-by-step walkthrough of every step in `action.yml`, with diagrams and rationale
- **[Roadmap](docs/ROADMAP.md)** - planned features, completed milestones
- **[Changelog](CHANGELOG.md)** - version history
- **[Security](SECURITY.md)** - vulnerability reporting and security practices
- **[Contributing](CONTRIBUTING.md)** - how to contribute

---

## Privacy

This action collects no data. No telemetry, no analytics, no external calls beyond Cloudflare itself. All processing happens on your GitHub Actions runner. The source is fully open - read every line in [`action.yml`](action.yml).

---

## License

[Apache 2.0](LICENSE) - © 2026 [NX1X](https://github.com/NX1X)
