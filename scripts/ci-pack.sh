#!/bin/sh
# Pack the prepared workspace and tool tree for later Gitea jobs.
# Check jobs restore this archive instead of cloning or installing tools.
set -eu

dest="${1:-${CI_ENV_TAR:-ci-env.tar.gz}}"
work="${CI_WORKSPACE:-${GITHUB_WORKSPACE:-.}}"
opt="${CI_OPT_CI:-/opt/ci}"
pack_debs="${CI_PACK_DEBS:-0}"
pack_opam="${CI_PACK_OPAM:-0}"

case "$dest" in
  /*) ;;
  *) dest="$(pwd)/$dest" ;;
esac

if [ ! -d "$work" ]; then
  echo "missing workspace $work" >&2
  exit 1
fi
if [ ! -d "$opt" ]; then
  echo "missing $opt; install the shared toolset before packing" >&2
  exit 1
fi

stage="$(mktemp -d)"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

mkdir -p "$stage/work" "$stage/opt-ci"
tar -C "$work" \
  --exclude=.git \
  --exclude=./_build \
  --exclude=./ci-env.tar.gz \
  --exclude="$(basename "$dest")" \
  -cf - . | tar -C "$stage/work" -xf -
tar -C "$opt" -cf - . | tar -C "$stage/opt-ci" -xf -

if [ "$pack_opam" = "1" ] && [ -d /home/opam/.opam ]; then
  mkdir -p "$stage/opam"
  tar -C /home/opam/.opam -cf - . | tar -C "$stage/opam" -xf -
fi

if [ "$pack_debs" = "1" ]; then
  mkdir -p "$stage/debs"
  if ls /var/cache/apt/archives/*.deb >/dev/null 2>&1; then
    cp -a /var/cache/apt/archives/*.deb "$stage/debs/"
  fi
fi

extras=""
if [ -d "$stage/opam" ]; then
  extras="$extras opam"
fi
if [ -d "$stage/debs" ]; then
  extras="$extras debs"
fi
mkdir -p "$(dirname "$dest")"
# extras is a known set of optional tar members (opam, debs).
# shellcheck disable=SC2086
tar -C "$stage" -czf "$dest" work opt-ci $extras
echo "packed $dest"
ls -l "$dest"
