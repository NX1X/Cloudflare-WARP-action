# Contributing to cloudflare-warp-action

Thanks for your interest in contributing! Here's how to get started.

## How to Contribute

1. **Found a bug?** [Open an issue](https://github.com/NX1X/cloudflare-warp-action/issues/new?template=bug_report.yml)
2. **Have an idea?** [Request a feature](https://github.com/NX1X/cloudflare-warp-action/issues/new?template=feature_request.yml) or check the [Roadmap](docs/ROADMAP.md)
3. **Have a question?** Use [GitHub Discussions](https://github.com/NX1X/cloudflare-warp-action/discussions)
4. **Found a security issue?** Do NOT open a public issue - see [SECURITY.md](SECURITY.md) for private reporting
5. **Want to contribute code?** Fork the repo, make your changes, open a pull request

## Development Setup

```bash
# Clone the repo
git clone https://github.com/NX1X/cloudflare-warp-action.git
cd cloudflare-warp-action

# Install linting tools (optional, CI runs these automatically)
# actionlint: https://github.com/rhysd/actionlint
# shellcheck: https://github.com/koalaman/shellcheck
```

## Development Workflow

1. Create a branch from `main`
2. Make your changes to `action.yml`, `cleanup/action.yml`, or workflows
3. Run quality checks locally (if tools are installed):
   ```bash
   actionlint
   shellcheck -x <(yq '.runs.steps[].run' action.yml)
   ```
4. Update `CHANGELOG.md` under the `[Unreleased]` section
5. Open a pull request

## Code Standards

- **Shell**: All `run:` blocks use `bash`
- **Linting**: Must pass `actionlint` and `shellcheck`
- **Secrets**: Always use `env:` blocks - never inline secrets in `run:` commands. CI explicitly checks that `inputs.auth-client-id` and `inputs.auth-client-secret` never appear inside `run:` blocks.
- **MDM file permissions**: `chmod 600`, owned by `root:root`. Write via `mktemp` + `install`, not `sudo tee`.
- **Credential redaction**: Any step that prints content potentially containing credentials must filter through `sed` to redact `<string>` values, Device IDs, Account IDs, etc.
- **Input validation**: Add validation for any new input that takes a value matched against an enum or constrained pattern. Reject unknown values with a clear error message before invoking `warp-cli`.

## Changelog

- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format
- Categorize: Added, Changed, Deprecated, Removed, Fixed, Security
- Add entries under `[Unreleased]`

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add macOS runner support
fix: handle warp-svc startup race on slow runners
docs: update troubleshooting table
ci: upgrade actions/checkout to v7
security: write MDM file via mktemp to avoid sudo cmdline exposure
```

## Pull Requests

- Fill out the PR template completely
- Reference any related issues
- Keep PRs focused - one fix or feature per PR
- All CI checks (lint + unit tests) must pass before merge
