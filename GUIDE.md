# Setup Guide

Complete walkthrough for `cloudflare-warp-action` - from Cloudflare Zero Trust setup to working CI/CD pipelines that reach internal infrastructure.

---

## How It Works

```
GitHub Actions Runner
      │
      │  warp-cli connect (auto via MDM service token)
      ▼
Cloudflare WARP edge ──── enroll device (Service Auth policy)
      │
   WARP tunnel (TUN interface on the runner)
      │
      ▼
Your internal network: 10.0.0.0/8, 172.16.0.0/12, internal DNS
```

The runner gets an IP on your WARP network. Any tool that opens a TCP/UDP socket to an internal IP or hostname is transparently routed through Cloudflare's edge to your internal network. There's no per-tool configuration - `ssh`, `psql`, `curl`, `kubectl`, etc. all work without changes.

---

## Step 1 - Set Up a Cloudflare Zero Trust Organization

If you don't already have a Zero Trust team set up:

1. Go to the [Cloudflare dashboard](https://dash.cloudflare.com) and select your account.
2. Click **Zero Trust** in the sidebar.
3. Choose a **team name** (this becomes your subdomain at `<team>.cloudflareaccess.com`).
4. Pick the **Free** plan (works for up to 50 users).

Your team name is what you'll pass to the action as `organization`.

---

## Step 2 - Make Your Internal Network Reachable via WARP

WARP needs to know which IPs to route through your network. The two main options:

### Option A: Cloudflare Tunnel + Private Network Route (recommended)

Run `cloudflared` on a machine inside your network and add a private network route:

```bash
# On the in-network machine
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
cloudflared tunnel login
cloudflared tunnel create internal-network
```

In the Zero Trust dashboard:

1. Go to **Networks** → **Tunnels** → select your tunnel
2. Click the **Private Network** tab → **Add a private network**
3. Enter your CIDR (e.g. `10.0.0.0/8`)

Now any IP in `10.0.0.0/8` is reachable to WARP-enrolled devices via this tunnel.

### Option B: WARP Connector

Use a [WARP Connector](https://developers.cloudflare.com/cloudflare-one/team-and-resources/connect-networks/warp-connector/) for a site-to-site connection. Suitable for larger deployments.

---

## Step 3 - Create a Device Enrollment Policy with Service Auth

This is what allows the GitHub Actions runner (a "device") to enroll automatically using a service token.

1. Go to Zero Trust → **Settings** → **WARP Client** → **Device enrollment permissions**
2. Click **Add a rule**
3. Set **Action: Service Auth**
4. Under **Selector**, choose:
   - **Any Access Service Token** (allows any service token), or
   - **Service Token** (restrict to a specific token created in Step 4)
5. Save the rule

> **Why Service Auth and not Allow?** "Allow" rules require interactive authentication (browser SSO). "Service Auth" is the only action that works headlessly with service tokens.

---

## Step 4 - Create a Service Token

1. Zero Trust → **Access** → **Service Auth** → **Service Tokens**
2. Click **Create Service Token**
3. Name it (e.g. `github-actions-warp`)
4. Set the duration (the maximum is 1 year - rotate before expiry)
5. **Copy the Client ID and Client Secret immediately** - you will not see the secret again

If your enrollment policy from Step 3 is restricted to a specific token, edit it now to attach this token.

---

## Step 5 - Add GitHub Secrets

Go to your repository → **Settings** → **Secrets and variables** → **Actions**.

| Secret | Value |
|--------|-------|
| `CF_WARP_ORG` | Your team name (just the subdomain, e.g. `acme-corp`) |
| `CF_WARP_CLIENT_ID` | Service token Client ID |
| `CF_WARP_CLIENT_SECRET` | Service token Client Secret |

Optional: `WARP_TEST_HOST` for the manual `Test Action` workflow (an internal hostname/IP to ping during smoke tests).

> **Tip:** Use a GitHub **Environment** (e.g. `prod`) for these secrets so you can require manual approval before deployments run.

---

## Step 6 - Use the Action

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - uses: actions/checkout@v6

      - uses: NX1X/cloudflare-warp-action@v1
        with:
          organization:        ${{ secrets.CF_WARP_ORG }}
          auth-client-id:      ${{ secrets.CF_WARP_CLIENT_ID }}
          auth-client-secret:  ${{ secrets.CF_WARP_CLIENT_SECRET }}

      - name: Deploy to internal server
        env:
          INTERNAL_HOST: app.internal.corp
        run: |
          ssh "deploy@${INTERNAL_HOST}" "cd ~/app && docker compose up -d"

      - uses: NX1X/cloudflare-warp-action/cleanup@v1
        if: always()
```

---

## Input Variations

Pin a specific WARP mode (default is full tunnel):

```yaml
mode: 'proxy'   # local SOCKS5/HTTP proxy on 127.0.0.1:40000
```

Send everything except GitHub through WARP (keep artifact uploads, container pulls, etc. direct):

```yaml
exclude-routes: |
  140.82.112.0/20
  143.55.64.0/20
  185.199.108.0/22
  192.30.252.0/22
```

Only send your internal RFC1918 ranges through WARP (smallest blast radius):

```yaml
include-routes: |
  10.0.0.0/8
  172.16.0.0/12
  192.168.0.0/16
```

Verify routing works before continuing the workflow:

```yaml
test-host:    db.internal.corp
retry-count:  '5'
retry-delay:  '10'
```

Skip the connection check entirely (you'll find out via your downstream commands):

```yaml
test-connection: 'false'
```

Pin the action for reproducibility:

| Style | Tag | Behavior |
|-------|-----|----------|
| Major | `@v1` | Auto-receives minor + patch updates (recommended) |
| Exact | `@v1.0.0` | Pinned, no automatic updates |
| SHA | `@abc1234` | Maximum reproducibility |

---

## Examples

### Integration tests against multiple internal services

```yaml
name: Integration Tests
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v6

      - uses: NX1X/cloudflare-warp-action@v1
        with:
          organization:       ${{ secrets.CF_WARP_ORG }}
          auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
          auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
          test-host:          db.staging.internal

      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }

      - run: npm ci
      - name: Run integration tests
        env:
          DB_HOST: db.staging.internal
          REDIS_HOST: redis.staging.internal
          API_BASE: http://api.staging.internal
        run: npm run test:integration

      - uses: NX1X/cloudflare-warp-action/cleanup@v1
        if: always()
```

### Terraform/Ansible against internal inventory

```yaml
name: Apply Infrastructure
on:
  workflow_dispatch:

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - uses: actions/checkout@v6

      - uses: NX1X/cloudflare-warp-action@v1
        with:
          organization:       ${{ secrets.CF_WARP_ORG }}
          auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
          auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
          include-routes: |
            10.0.0.0/8
            172.16.0.0/12

      - uses: hashicorp/setup-terraform@v3
      - run: terraform init && terraform apply -auto-approve

      - uses: NX1X/cloudflare-warp-action/cleanup@v1
        if: always()
```

### Pull from an internal container registry

```yaml
name: Build & Push to Internal Registry
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: NX1X/cloudflare-warp-action@v1
        with:
          organization:       ${{ secrets.CF_WARP_ORG }}
          auth-client-id:     ${{ secrets.CF_WARP_CLIENT_ID }}
          auth-client-secret: ${{ secrets.CF_WARP_CLIENT_SECRET }}
          # Keep ghcr.io / Docker Hub direct
          exclude-routes: |
            140.82.112.0/20

      - name: Build and push to internal Harbor
        env:
          REGISTRY: harbor.internal.corp
          IMAGE: myapp
        run: |
          echo "${{ secrets.HARBOR_PASSWORD }}" \
            | docker login "$REGISTRY" -u "${{ secrets.HARBOR_USER }}" --password-stdin
          docker build -t "${REGISTRY}/${IMAGE}:${GITHUB_SHA}" .
          docker push "${REGISTRY}/${IMAGE}:${GITHUB_SHA}"

      - uses: NX1X/cloudflare-warp-action/cleanup@v1
        if: always()
```

---

## Using Outputs

```yaml
steps:
  - uses: NX1X/cloudflare-warp-action@v1
    id: warp
    with: { ... }

  - name: Show WARP info
    run: |
      echo "WARP version: ${{ steps.warp.outputs.warp-version }}"
      echo "Status: ${{ steps.warp.outputs.connection-status }}"
      echo "Tunnel IP: ${{ steps.warp.outputs.warp-ip }}"

  - name: Only continue if connected
    if: steps.warp.outputs.connection-status == 'connected'
    run: ./deploy.sh
```

| Output | Values |
|--------|--------|
| `warp-version` | e.g. `2024.6.415` |
| `connection-status` | `connected`, `failed`, `skipped` |
| `warp-ip` | e.g. `100.96.1.42` (empty for `mode=doh`) |

---

## Troubleshooting

### `Device registration did not complete within 60 seconds`

The MDM file was written but the daemon couldn't authenticate:

1. Verify your `auth-client-id` / `auth-client-secret` are correct in GitHub Secrets
2. Verify your **Device enrollment** rule has Action set to **Service Auth** (not Allow)
3. Verify the rule's selector includes the service token you're using (or "Any Access Service Token")
4. Check `journalctl -u warp-svc -b` in the action log for daemon errors
5. Confirm your Zero Trust team name (`organization`) is the subdomain only, not the full URL

### `WARP failed to reach Connected state`

The daemon registered but couldn't bring up the tunnel:

1. Try increasing `retry-count` and `retry-delay` (the WARP edge can take several seconds on cold start)
2. Check the GitHub-hosted runner's network: WARP needs UDP outbound on port 2408 (WireGuard) or 443 (MASQUE)
3. Try `mode: warp+doh` if `mode: warp` fails - it can sometimes negotiate when plain WARP can't

### `ping <internal-host>: Network is unreachable`

WARP is connected but the internal hostname isn't routable:

1. Confirm the IP/hostname is part of a private network route on your Cloudflare Tunnel
2. Confirm DNS resolution: `nslookup db.internal.corp` should return an IP in your private range
3. If using `include-routes`, make sure the destination CIDR is in the include list

### `lsb_release: command not found`

You're on a non-Ubuntu/Debian runner. This action only supports `ubuntu-*` runners.

### `auth_client_id missing from action.yml` (CI failure)

You modified `action.yml` and the structural validation in CI caught it. The CI checks that the MDM keys (`organization`, `auth_client_id`, `auth_client_secret`, `service_mode`, `auto_connect`) are all present.

---

## Cleanup

The action writes a credential-bearing file to `/var/lib/cloudflare-warp/mdm.xml`. On GitHub-hosted runners this is destroyed when the job ends, but for self-hosted runners or defense in depth, always run cleanup:

```yaml
- uses: NX1X/cloudflare-warp-action/cleanup@v1
  if: always()
```

The cleanup action:
- Disconnects WARP (`warp-cli disconnect`)
- Deletes the device registration (`warp-cli registration delete`)
- Removes the MDM file at `/var/lib/cloudflare-warp/mdm.xml`
- Removes the state file at `~/.cloudflare-warp-state`

To fully uninstall the package and remove the apt repo:

```yaml
- uses: NX1X/cloudflare-warp-action/cleanup@v1
  if: always()
  with:
    remove-warp: 'true'
```
