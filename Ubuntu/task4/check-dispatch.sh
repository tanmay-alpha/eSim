#!/usr/bin/env bash
# Run inside Ubuntu 25.04. Decline removal; never request elevated privileges.
set -eu
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 25.04 ]] || { echo 'Requires Ubuntu 25.04' >&2; exit 1; }
wrapper=$(dirname "$0")/../install-eSim.sh
output=$(printf 'n\n' | bash "$wrapper" --uninstall)
printf '%s\n' "$output"
[[ $output == *'install-eSim-25.04.sh --uninstall'* && $output == *'Are you sure?'* ]]
# No answer to the install prompt: the backend's read fails. Its nonzero
# status must reach the caller, not be replaced by the dispatcher's status.
if bash "$wrapper" --install </dev/null; then exit 1; else [[ $? == 1 ]]; fi
