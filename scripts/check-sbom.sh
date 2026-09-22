#!/bin/sh
# Fail when a direct opam dependency is absent from the CycloneDX SBOM.
# depopts are optional and are not required. Constraint strings inside
# {...} are versions, not package names.
set -eu

opam_file="${1:-carolina_fstar.opam}"
sbom="${2:-opam-deps.cdx.json}"

if [ ! -f "$opam_file" ]; then
  echo "missing opam file $opam_file" >&2
  exit 1
fi
if [ ! -f "$sbom" ]; then
  echo "missing sbom $sbom" >&2
  exit 1
fi

block="$(sed -n '/^depends:/,/^]/p' "$opam_file" | sed 's/{[^}]*}//g')"
names="$(printf '%s\n' "$block" | grep -o '"[^"]*"' | tr -d '"' | sort -u)"

if [ -z "$names" ]; then
  echo "no direct dependencies parsed from $opam_file" >&2
  exit 1
fi

missing=0
for name in $names; do
  if ! grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\"" "$sbom"; then
    echo "sbom missing direct opam dependency: $name" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "sbom includes direct opam dependencies"
