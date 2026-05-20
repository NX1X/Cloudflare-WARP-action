## Description

<!-- What does this PR do? Link any related issues. -->

Closes #

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Security fix

## Checklist

- [ ] I have updated `CHANGELOG.md` (under `[Unreleased]`)
- [ ] `actionlint` passes
- [ ] Shell scripts pass `shellcheck`
- [ ] Unit tests (`unit-tests.yml`) pass - added new tests for new logic where applicable
- [ ] I have tested the action locally or via the Test Action workflow against a real Cloudflare Zero Trust org
- [ ] If this PR adds/changes inputs that take credentials, they are routed through `env:` blocks (not inlined in `run:`) and the CI structural check still passes
- [ ] If this PR touches the MDM file logic, the file remains `chmod 600` root-owned and credentials are never written to a sudo command line
