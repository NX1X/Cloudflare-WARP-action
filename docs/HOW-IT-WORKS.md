# How It Works

A detailed walkthrough of what `cloudflare-warp-action` does internally - step by step,
with diagrams and annotated code.

---

## Overview

This action installs the **Cloudflare WARP client** on a GitHub Actions runner and enrolls
the runner as a "device" in your Cloudflare Zero Trust organization. Once enrolled and
connected, the runner has a TUN network interface (`CloudflareWARP`) and any tool that
opens a socket to an internal IP/hostname is transparently routed through Cloudflare's
edge to your private network.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GitHub Actions Runner                                                   │
│                                                                          │
│  ssh deploy@app.internal.corp "docker compose up -d"                     │
│    │                                                                     │
│    ├─ kernel routes packets to app.internal.corp via CloudflareWARP      │
│    │    interface (WARP IP, e.g. 100.96.1.42)                            │
│    │                                                                     │
│    └─ packets encapsulated by warp-svc, sent to Cloudflare edge          │
│         │                                                                │
└─────────┼────────────────────────────────────────────────────────────────┘
          │  WireGuard / MASQUE (encrypted)
          ▼
┌─────────────────────────┐
│   Cloudflare Network    │
│   (Zero Trust + Edge)   │
└─────────┬───────────────┘
          │  Tunnel / WARP Connector
          ▼
┌─────────────────────────┐
│   Your private network  │
│   10.0.0.0/8            │
│   app.internal.corp     │
│   (no public IPs)       │
└─────────────────────────┘
```

After the action runs, **every** TCP/UDP socket opened to a routable internal IP/hostname
flows through this chain. No per-tool configuration needed.

---

## Step-by-Step Walkthrough

The action is a [composite action](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action)
with 11 sequential steps. [`action.yml`](../action.yml) is a thin YAML wrapper -
each step delegates to a standalone shell script under [`scripts/`](../scripts/),
which is what the unit-test suite exercises directly. The "Implementation" link
at the top of each step below points to the script that contains its logic.

---

### Step 1: Validate inputs

**Implementation:** [`scripts/01-validate-inputs.sh`](../scripts/01-validate-inputs.sh) (sources [`scripts/lib/validate.sh`](../scripts/lib/validate.sh))

**What it does:** Checks `mode`, `retry-count`, `retry-delay`, `organization`, and CIDR
ranges in `exclude-routes` / `include-routes` against strict patterns. Rejects unknown or
malformed values before invoking any privileged operation.

```bash
case "$MODE" in
  warp|proxy|doh|warp+doh) ;;
  *) echo "ERROR: Invalid mode '$MODE'"; exit 1 ;;
esac

if ! echo "$ORGANIZATION" | grep -qE '^[a-z0-9][a-z0-9-]{0,62}$'; then
  echo "ERROR: organization must be the team subdomain only"
  exit 1
fi

# exclude-routes and include-routes are mutually exclusive
if [ -n "$EXCLUDE_ROUTES" ] && [ -n "$INCLUDE_ROUTES" ]; then
  echo "ERROR: exclude-routes and include-routes are mutually exclusive"
  exit 1
fi
```

**Why:** Catching bad input here turns a confusing downstream `warp-cli` error into a
clear `ERROR: Invalid mode 'WARP' - expected one of: warp, proxy, doh, warp+doh`. Also
prevents shell-metacharacter injection from input values that flow into shell commands.

---

### Step 2: Install the cloudflare-warp client

**Implementation:** [`scripts/02-install-warp.sh`](../scripts/02-install-warp.sh)

**What it does:** Adds Cloudflare's apt repository, imports the GPG key, installs the
`cloudflare-warp` package, and captures the installed version into the `warp-version`
output.

```bash
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

DISTRO_CODENAME=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${DISTRO_CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list > /dev/null

sudo apt-get update --assume-yes
sudo apt-get install --assume-yes cloudflare-warp
```

**Why apt instead of a direct `.deb` download?** The Cloudflare repo handles dependency
resolution (kernel modules, systemd integration) and signs the package via the GPG
keyring. Using apt also makes uninstall via the cleanup step a one-liner.

**Ubuntu/Debian only:** The Cloudflare WARP repo only ships `.deb` packages. The action
checks for `lsb_release` and exits with a clear error otherwise.

---

### Step 3: Wait for the warp-svc daemon

**Implementation:** [`scripts/03-wait-daemon.sh`](../scripts/03-wait-daemon.sh) (uses `wait_for_daemon` from [`scripts/lib/common.sh`](../scripts/lib/common.sh))

**What it does:** Polls `warp-cli status` for up to 30 seconds until the daemon's IPC
socket responds.

```bash
for i in $(seq 1 30); do
  if warp-cli --accept-tos status > /dev/null 2>&1; then
    echo "warp-svc is ready (took ${i}s)"
    exit 0
  fi
  sleep 1
done
```

**Why:** `apt install cloudflare-warp` starts `warp-svc` via systemd, but the IPC socket
isn't always reachable the moment `dpkg` returns. Racing the daemon causes spurious
"daemon not running" errors in the next step. Waiting up to 30s is a cheap way to make
the action resilient on slow runners.

---

### Step 4: Write the MDM configuration file

**Implementation:** [`scripts/04-write-mdm.sh`](../scripts/04-write-mdm.sh)

**What it does:** Writes a plist-style XML file to `/var/lib/cloudflare-warp/mdm.xml`
with the service-token credentials and connection mode.

```xml
<dict>
    <key>organization</key>
    <string>acme-corp</string>
    <key>auth_client_id</key>
    <string>abc123.access</string>
    <key>auth_client_secret</key>
    <string>...</string>
    <key>service_mode</key>
    <string>warp</string>
    <key>auto_connect</key>
    <integer>1</integer>
    <key>onboarding</key>
    <false/>
    <key>switch_locked</key>
    <true/>
</dict>
```

This is the most critical step. Three design decisions matter here:

#### Why MDM instead of `warp-cli teams-enroll --auth-client-id ...`?

The CLI flags `--auth-client-id` and `--auth-client-secret` were **removed** in recent
`warp-cli` versions (`warp-cli teams-enroll` is being deprecated entirely). The official
Cloudflare-supported path for headless service-token enrollment is the MDM XML file.
Source: [Deploy WARP on headless Linux machines](https://developers.cloudflare.com/cloudflare-one/tutorials/warp-on-headless-linux/).

When `warp-svc` starts and finds an MDM file, it auto-registers the device using the
embedded credentials and (with `auto_connect: 1`) connects. No browser, no interactive
prompt, no CLI flags.

#### Why `mktemp` + `install` instead of `sudo tee`?

```bash
TMP_MDM=$(mktemp)                                          # 0600 by default
{ printf '<dict>...'; ... } > "$TMP_MDM"
sudo install -m 600 -o root -g root "$TMP_MDM" /var/lib/cloudflare-warp/mdm.xml
rm -f "$TMP_MDM"
```

If we used `echo "$AUTH_CLIENT_SECRET" | sudo tee /var/lib/...`, the secret would briefly
appear on the `sudo` command line and be visible in `/proc/<pid>/cmdline` to any user on
the system. `mktemp` + `install` avoids that - the secret only ever lives in the temp
file (mode 0600, owner = runner user) and the final destination (mode 0600, owner = root).

#### Why root-owned, mode 0600?

The `warp-svc` daemon runs as root. It's the only process that needs to read the file.
Any other user on the system (including the runner user after `sudo install`) cannot
read it - the credentials are at rest under the strictest permissions Linux offers.

---

### Step 5: Restart `warp-svc` and wait for registration

**Implementation:** [`scripts/05-restart-and-register.sh`](../scripts/05-restart-and-register.sh) (uses `wait_for_daemon` and `wait_for_registration` from [`scripts/lib/common.sh`](../scripts/lib/common.sh), plus `redact_registration` for the masked output)

**What it does:** Restarts the daemon (so it picks up the new MDM file), waits for it to
come back up, then polls `warp-cli registration show` until registration completes.

```bash
sudo systemctl restart warp-svc

# Wait for daemon
for i in $(seq 1 30); do
  if warp-cli --accept-tos status > /dev/null 2>&1; then break; fi
  sleep 1
done

# Wait for auto-registration via MDM
for i in $(seq 1 60); do
  if warp-cli --accept-tos registration show > /dev/null 2>&1; then
    warp-cli --accept-tos registration show 2>&1 \
      | sed -E 's/(Device ID:|Account ID:|Public Key:|Token:)[[:space:]]*.*/\1 <REDACTED>/g'
    exit 0
  fi
  sleep 1
done
```

**Why two waits?** The daemon comes up first (~1-3s), then the auto-registration handshake
with the Cloudflare edge happens (~2-15s depending on edge load). Bundling them into one
poll would obscure where a stall is happening - separating them gives a clearer error
message ("daemon down" vs "registration timeout").

**Redaction:** The output of `registration show` includes the Device ID, Account ID, and
public key - none of these are secrets per se, but they uniquely identify the runner
to your Cloudflare org and shouldn't appear in public CI logs.

---

### Step 6: Configure split-tunnel routes (optional)

**Implementation:** [`scripts/06-split-tunnel.sh`](../scripts/06-split-tunnel.sh)

**What it does:** If `exclude-routes` or `include-routes` is set, adds each CIDR via
`warp-cli tunnel ip add <CIDR> exclude|include`. Falls back to the legacy
`add-excluded-route` / `add-included-route` form on older `warp-cli` versions.

```bash
add_route() {
  local cidr="$1" mode="$2"
  if warp-cli --accept-tos tunnel ip add "$cidr" "$mode" 2>/dev/null; then
    return 0
  fi
  if [ "$mode" = "exclude" ]; then
    warp-cli --accept-tos add-excluded-route "$cidr"
  else
    warp-cli --accept-tos add-included-route "$cidr"
  fi
}
```

**Why fallback?** The new `tunnel ip add` form was introduced in 2024.x. Older versions
of the package still ship in some Debian repos. Trying new first, falling back to legacy
keeps the action working across both.

---

### Step 7: Connect WARP

**Implementation:** [`scripts/07-connect.sh`](../scripts/07-connect.sh)

**What it does:** Calls `warp-cli connect` to bring up the tunnel.

```bash
warp-cli --accept-tos connect || true
```

**Why `|| true`?** `auto_connect: 1` in the MDM file usually causes the daemon to connect
automatically when registration completes. In that case `warp-cli connect` is a no-op or
returns "already connected" with a non-zero exit code on some versions. We don't care -
the verification step in Step 8 is what actually proves connectivity.

---

### Step 8: Verify connection (with retry)

**Implementation:** [`scripts/08-verify-connection.sh`](../scripts/08-verify-connection.sh)

**What it does:** Polls `warp-cli status` until it shows "Connected", with optional
post-connection ping to a `test-host` to verify routing works end-to-end.

```bash
ATTEMPT=1
while [ "$ATTEMPT" -le "$RETRY_COUNT" ]; do
  STATUS_OUT=$(warp-cli --accept-tos status 2>&1)
  if echo "$STATUS_OUT" | grep -qiE 'Status update: Connected|Status: Connected'; then
    STATUS_OK=true; break
  fi
  sleep "$RETRY_DELAY"
  ATTEMPT=$((ATTEMPT + 1))
done

if [ -n "$TEST_HOST" ]; then
  for i in $(seq 1 "$RETRY_COUNT"); do
    if ping -c 1 -W 5 "$TEST_HOST" > /dev/null 2>&1; then break; fi
    sleep "$RETRY_DELAY"
  done
fi
```

**Why two status string variants?** Different `warp-cli` versions print the status with
or without the "update:" prefix. Matching both keeps the action stable across versions.

**Why ping?** Status saying "Connected" means the daemon thinks the tunnel is up. Pinging
`test-host` proves that packets actually reach your private network - catching policy
misconfigurations, missing private network routes, or DNS issues that wouldn't otherwise
surface until your real downstream commands fail.

---

### Step 9: Set connection-status output (skipped path)

**Implementation:** [`scripts/set-skipped-status.sh`](../scripts/set-skipped-status.sh)

**What it does:** When `test-connection: 'false'`, this step runs instead and writes
`connection-status=skipped` to the output.

The action's `connection-status` output uses a fallback expression:

```yaml
connection-status:
  value: ${{ steps.verify-connection.outputs.connection-status || steps.verify-skipped.outputs.connection-status }}
```

Exactly one of the two steps runs, so exactly one writes a value.

---

### Step 10: Capture WARP IP

**Implementation:** [`scripts/09-capture-ip.sh`](../scripts/09-capture-ip.sh)

**What it does:** Reads the IPv4 address bound to the `CloudflareWARP` TUN interface and
writes it to the `warp-ip` output.

```bash
WARP_IP=""
if ip -4 addr show CloudflareWARP > /dev/null 2>&1; then
  WARP_IP=$(ip -4 -o addr show CloudflareWARP | awk '{print $4}' | cut -d/ -f1 | head -n1)
fi
echo "warp-ip=${WARP_IP}" >> "$GITHUB_OUTPUT"
```

**Why parse the interface directly?** The WARP IP is what your downstream tools will use
as their source address when reaching internal services. Reading it from the kernel's
view of the interface is more reliable than parsing `warp-cli` output (which varies
across versions).

For `mode: doh`, there's no tunnel and no `CloudflareWARP` interface - `warp-ip` is
written as an empty string.

---

### Step 11: Write cleanup state file

**Implementation:** [`scripts/10-write-state.sh`](../scripts/10-write-state.sh)

**What it does:** Writes a small file at `~/.cloudflare-warp-state` containing the paths
and flags the cleanup sub-action needs.

```
MDM_PATH=/var/lib/cloudflare-warp/mdm.xml
REGISTERED=true
INSTALLED=true
```

**No credentials.** Unlike the MDM file, this state file holds only paths and boolean
flags - safe to leave in `$HOME` even on self-hosted runners. The cleanup sub-action reads
this to know what to disconnect, what to unregister, and what to remove.

---

## Credential Flow

Complete path of secrets from GitHub to the runner:

```
GitHub Secrets (encrypted at rest)
  │  ${{ secrets.CF_WARP_ORG }}
  │  ${{ secrets.CF_WARP_CLIENT_ID }}
  │  ${{ secrets.CF_WARP_CLIENT_SECRET }}
  ▼
action.yml inputs (masked in logs by GitHub Actions)
  │  organization        ──► env: ORGANIZATION
  │  auth-client-id      ──► env: AUTH_CLIENT_ID
  │  auth-client-secret  ──► env: AUTH_CLIENT_SECRET
  ▼
Written to disk (via mktemp, then `install` to root-owned destination)
  │  /var/lib/cloudflare-warp/mdm.xml   chmod 600, owner root:root
  ▼
Read by warp-svc (running as root)
  │  Daemon authenticates to Cloudflare edge using these credentials
  ▼
Cloudflare edge issues device registration token
  │  Stored in warp-svc's internal database (also root-only)
  ▼
After workflow ends (GitHub-hosted runner)
  │  Runner VM destroyed - all files gone with it
  ▼
After workflow ends (self-hosted runner with cleanup sub-action)
  │  cleanup runs warp-cli disconnect + warp-cli registration delete
  │  cleanup removes /var/lib/cloudflare-warp/mdm.xml
  │  cleanup removes ~/.cloudflare-warp-state
```

The only network destination receiving credentials is the Cloudflare edge itself.

---

## Security Model

### File permissions summary

| File | Permissions | Owner | Contents | Masked in logs? |
|------|-------------|-------|----------|-----------------|
| `/var/lib/cloudflare-warp/mdm.xml` | `600` | `root:root` | Service token credentials | Yes (via `env:`) |
| `~/.cloudflare-warp-state` | default (`644`) | runner user | Paths + flags only | n/a (no secrets) |

### What's redacted in logs

- **GitHub Actions masking:** All values passed through `env:` from `${{ secrets.* }}`
  are automatically masked (replaced with `***`) in workflow logs.
- **MDM verify step:** The MDM file is printed with all `<string>...</string>` values
  replaced by `<string><REDACTED></string>` - keys are visible (so you can confirm the
  schema), values are not.
- **Registration show:** Device ID, Account ID, Public Key, and Token lines are
  filtered through `sed` to redact the trailing values.

### Runner lifecycle

GitHub-hosted runners are ephemeral VMs. After the workflow completes, the runner is
destroyed and the MDM file goes with it. Self-hosted runners persist - for those, run
the cleanup sub-action with `if: always()` so the MDM file (which is the only
credential-bearing artifact) is removed even when the job fails.

---

## Further Reading

- [README](../README.md) - quick start, inputs reference, supported runners
- [GUIDE.md](../GUIDE.md) - full Cloudflare Zero Trust setup walkthrough
- [SECURITY.md](../SECURITY.md) - vulnerability reporting, threat model
- [ROADMAP.md](ROADMAP.md) - planned features
- [Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/) - Zero Trust, WARP, Tunnels
- [Headless WARP deployment guide](https://developers.cloudflare.com/cloudflare-one/tutorials/warp-on-headless-linux/) - official MDM-based deployment
