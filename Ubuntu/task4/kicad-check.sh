#!/usr/bin/env bash
# Destructive package-install check: run as root in a fresh ubuntu:25.04
# container with current Plucky archive + kicad/kicad-8.0-releases PPA indexes.
set -eu
. /etc/os-release
[[ $EUID == 0 && $ID == ubuntu && $VERSION_ID == 25.04 ]] || exit 2
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
packages=(kicad-footprints kicad-libraries kicad-symbols kicad-templates)
apt-cache policy kicad "${packages[@]}" libgit2-1.8 libgit2-1.9
# Compare the default candidate to the exact command used by the installer.
# Simulation of the control avoids installing an incompatible version.
printf '\nDefault candidate (simulation):\n'
rc=0; apt-get -s install --no-install-recommends kicad "${packages[@]}" || rc=$?
printf 'Default candidate exit: %s\n' "$rc"
printf '\nInstaller selection (actual installation):\n'
rc=0; apt-get install -y --no-install-recommends kicad=8.0.8+dfsg-1 "${packages[@]}" || rc=$?
printf 'Pinned install exit: %s\n' "$rc"
(( rc == 0 )) || exit "$rc"
dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' kicad "${packages[@]}" libgit2-1.9
version=$(kicad-cli version)
printf 'kicad-cli version: %s\n' "$version"
[[ $version == 8.* ]]
