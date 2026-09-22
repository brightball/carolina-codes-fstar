#!/bin/sh
# Restore the prepared CI workspace and tool tree packed by scripts/ci-pack.sh.
# When CI_ENV_TAR points at a tarball, unpack it. Otherwise download the
# Gitea artifact named ci-env. Do not install the shared toolset.
set -eu

archive="${CI_ENV_TAR:-/tmp/ci-env.tar.gz}"
work="${CI_WORKSPACE:-${GITHUB_WORKSPACE:-.}}"
opt="${CI_OPT_CI:-/opt/ci}"

if [ ! -f "$archive" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
  if [ -f "${script_dir}/ci-artifact.sh" ]; then
    sh "${script_dir}/ci-artifact.sh" download ci-env "$archive"
  else
    echo "missing $archive and scripts/ci-artifact.sh" >&2
    exit 1
  fi
fi

stage="$(mktemp -d)"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

tar -xzf "$archive" -C "$stage"
if [ ! -d "$stage/work" ] || [ ! -d "$stage/opt-ci" ]; then
  echo "restored archive is missing work/ or opt-ci/" >&2
  exit 1
fi

mkdir -p "$work" "$opt"
tar -C "$stage/work" -cf - . | tar -C "$work" -xf -
tar -C "$stage/opt-ci" -cf - . | tar -C "$opt" -xf -

system_restore=0
if [ "${CI_RESTORE_SYSTEM:-auto}" = "1" ]; then
  system_restore=1
elif [ "${CI_RESTORE_SYSTEM:-auto}" = "auto" ] && [ "$(id -u)" = "0" ]; then
  system_restore=1
fi

if [ "$system_restore" = "1" ]; then
  if [ -d "$stage/opam" ]; then
    mkdir -p /home/opam/.opam
    tar -C "$stage/opam" -cf - . | tar -C /home/opam/.opam -xf -
  fi
  if [ -d "$stage/debs" ] && ls "$stage/debs"/*.deb >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    dpkg --force-depends --install "$stage/debs"/*.deb
  fi
  if [ -d /usr/local/bin ]; then
    if [ -d "$opt/bin" ]; then
      cp -a "$opt/bin/." /usr/local/bin/
    fi
    if [ -x "$opt/semgrep/bin/semgrep" ]; then
      ln -sf "$opt/semgrep/bin/semgrep" /usr/local/bin/semgrep
    fi
    if [ -x "$opt/fstar/bin/fstar.exe" ]; then
      ln -sf "$opt/fstar/bin/fstar.exe" /usr/local/bin/fstar.exe
    fi
  fi
  if id opam >/dev/null 2>&1; then
    chown -R opam:opam "$work" 2>/dev/null || true
    if [ -d /home/opam/.opam ]; then
      chown -R opam:opam /home/opam/.opam 2>/dev/null || true
    fi
  fi
  ldconfig 2>/dev/null || true
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$opt/bin" >> "$GITHUB_PATH"
  echo "$opt/semgrep/bin" >> "$GITHUB_PATH"
  echo "$opt/fstar/bin" >> "$GITHUB_PATH"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "FSTAR_HOME=$opt/fstar" >> "$GITHUB_ENV"
fi

echo "restored workspace=$work opt=$opt"
