#!/usr/bin/env bash
# Install the link toolchain (mold + clang) plus optional extra apt packages.
#
# apt on GitHub-hosted runners fails for hours at a time (archive.ubuntu.com
# outages have killed whole jobs here repeatedly — every job dies at this one
# step). mold installs fine from upstream release binaries, so fall back to
# them instead of failing the run. clang has no portable static fallback, but
# the runner image ships it; the script verifies every piece at the end.
#
# Usage: install-linker.sh [extra apt packages...]
#   install-linker.sh                 # mold + clang
#   install-linker.sh shellcheck      # mold + clang + shellcheck (with fallback)
set -euo pipefail

extra=("$@")
timeout_s=${APT_TIMEOUT:-240}

if timeout "$timeout_s" sudo apt-get update -qq -o Acquire::Retries=5 -o Acquire::http::Timeout=15 \
   && timeout "$timeout_s" sudo apt-get install -y -qq -o Acquire::Retries=5 -o Acquire::http::Timeout=15 \
        mold clang "${extra[@]}"; then
    echo ">>> link toolchain installed via apt"
    exit 0
fi

echo ">>> apt unavailable; falling back to upstream release binaries"

# mold: the main repo's .cargo/config.toml points at /usr/bin/mold (and dylint-link
# resolves it through PATH), so the install path is fixed.
gh release download v3.0.0 -R rui314/mold -p 'mold-*-x86_64-linux.tar.gz' -O /tmp/mold.tgz
tar -xzf /tmp/mold.tgz -C /tmp
sudo install -m755 /tmp/mold-*/bin/mold /usr/bin/mold
mold --version

command -v clang >/dev/null 2>&1 || {
    echo "clang is neither preinstalled nor installable (apt down); cannot fall back" >&2
    exit 1
}
clang --version

# Extras that ship static release binaries fall back too; anything else fails loudly.
for pkg in "${extra[@]}"; do
    case "$pkg" in
        shellcheck)
            gh release download v0.11.0 -R koalaman/shellcheck \
                -p 'shellcheck-v*.linux.x86_64.tar.xz' -O /tmp/shellcheck.tar.xz
            tar -xJf /tmp/shellcheck.tar.xz -C /tmp
            sudo install -m755 /tmp/shellcheck-v*/shellcheck /usr/local/bin/shellcheck
            shellcheck --version
            ;;
        *)
            echo "no release-binary fallback for '$pkg' and apt is down" >&2
            exit 1
            ;;
    esac
done
