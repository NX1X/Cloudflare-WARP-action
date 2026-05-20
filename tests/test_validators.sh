#!/usr/bin/env bash
# Tests for scripts/lib/validate.sh - sources the real validators.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"
# shellcheck source=../scripts/lib/validate.sh
. "$ROOT_DIR/scripts/lib/validate.sh"

echo "=== validate_mode ==="
assert_command_succeeds "warp is valid" validate_mode "warp"
assert_command_succeeds "proxy is valid" validate_mode "proxy"
assert_command_succeeds "doh is valid" validate_mode "doh"
assert_command_succeeds "warp+doh is valid" validate_mode "warp+doh"
assert_command_fails "empty rejected" validate_mode ""
assert_command_fails "WARP (uppercase) rejected" validate_mode "WARP"
assert_command_fails "tunnel typo rejected" validate_mode "tunnel"
assert_command_fails "command injection rejected" validate_mode '$(whoami)'

echo "=== validate_positive_int ==="
assert_command_succeeds "1 valid" validate_positive_int "1"
assert_command_succeeds "3 valid" validate_positive_int "3"
assert_command_succeeds "100 valid" validate_positive_int "100"
assert_command_fails "0 rejected" validate_positive_int "0"
assert_command_fails "-1 rejected" validate_positive_int "-1"
assert_command_fails "abc rejected" validate_positive_int "abc"
assert_command_fails "empty rejected" validate_positive_int ""
assert_command_fails "decimal rejected" validate_positive_int "3.5"
assert_command_fails "trailing space rejected" validate_positive_int "3 "
assert_command_fails "leading zero alone rejected" validate_positive_int "0123"

echo "=== validate_org ==="
assert_command_succeeds "acme valid" validate_org "acme"
assert_command_succeeds "acme-corp valid" validate_org "acme-corp"
assert_command_succeeds "team123 valid" validate_org "team123"
assert_command_succeeds "single char valid" validate_org "a"
assert_command_fails "empty rejected" validate_org ""
assert_command_fails "uppercase rejected" validate_org "ACME"
assert_command_fails "dot rejected" validate_org "acme.cloudflareaccess.com"
assert_command_fails "https URL rejected" validate_org "https://acme.cloudflareaccess.com"
assert_command_fails "underscore rejected" validate_org "acme_corp"
assert_command_fails "leading hyphen rejected" validate_org "-acme"
assert_command_fails "whitespace rejected" validate_org "acme corp"
assert_command_fails "too long rejected" validate_org "$(printf 'a%.0s' {1..64})"

echo "=== validate_cidr ==="
assert_command_succeeds "ipv4 /16 valid" validate_cidr "192.168.0.0/16"
assert_command_succeeds "ipv4 /24 valid" validate_cidr "10.0.0.0/24"
assert_command_succeeds "ipv4 /32 valid" validate_cidr "1.2.3.4/32"
assert_command_succeeds "ipv6 fd00 valid" validate_cidr "fd00::/8"
assert_command_succeeds "ipv6 full valid" validate_cidr "2001:db8::/32"
assert_command_fails "missing prefix rejected" validate_cidr "192.168.0.0"
assert_command_fails "garbage rejected" validate_cidr "not-an-ip"
assert_command_fails "empty rejected" validate_cidr ""
assert_command_fails "injection rejected" validate_cidr '10.0.0.0/8;rm -rf /'

echo "=== check_routes ==="
assert_command_succeeds "empty routes ok" check_routes "exclude-routes" ""
assert_command_succeeds "single v4 ok" check_routes "exclude-routes" "10.0.0.0/8"
assert_command_succeeds "multiline ok" check_routes "exclude-routes" "$(printf '10.0.0.0/8\n192.168.0.0/16\n')"
assert_command_succeeds "blank line ignored" check_routes "exclude-routes" "$(printf '10.0.0.0/8\n\n192.168.0.0/16\n')"
assert_command_succeeds "trims whitespace" check_routes "exclude-routes" "  10.0.0.0/8  "
assert_command_fails "bad cidr rejected" check_routes "exclude-routes" "not-a-cidr"
assert_command_fails "one bad among many" check_routes "exclude-routes" "$(printf '10.0.0.0/8\nbogus\n')"

echo "=== check_exclusivity ==="
assert_command_succeeds "both empty allowed" check_exclusivity "" ""
assert_command_succeeds "only exclude allowed" check_exclusivity "10.0.0.0/8" ""
assert_command_succeeds "only include allowed" check_exclusivity "" "10.0.0.0/8"
assert_command_fails "both rejected" check_exclusivity "10.0.0.0/8" "192.168.0.0/16"
