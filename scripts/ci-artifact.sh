#!/bin/sh
# Upload or download a Gitea Actions artifact via the v3 pipeline API (curl).
# No Node marketplace actions.
set -eu

usage() {
  echo "usage: $0 upload <name> <file>" >&2
  echo "       $0 download <name> <file>" >&2
  exit 2
}

cmd="${1:-}"
name="${2:-}"
file="${3:-}"
[ -n "$cmd" ] && [ -n "$name" ] && [ -n "$file" ] || usage

token="${ACTIONS_RUNTIME_TOKEN:-${GITHUB_TOKEN:-${GITEA_TOKEN:-}}}"
run_id="${GITHUB_RUN_ID:-${GITEA_RUN_ID:-${FORGEJO_RUN_ID:-}}}"
runtime="${ACTIONS_RUNTIME_URL:-}"
if [ -z "$runtime" ]; then
  runtime="${GITHUB_SERVER_URL:-}/api/actions_pipeline/"
fi
case "$runtime" in
  */) ;;
  *) runtime="${runtime}/" ;;
esac
api="${runtime}_apis/pipelines/workflows/${run_id}/artifacts"

if [ -z "$token" ]; then
  echo "missing ACTIONS_RUNTIME_TOKEN/GITHUB_TOKEN for artifacts" >&2
  exit 1
fi
if [ -z "$run_id" ]; then
  echo "missing GITHUB_RUN_ID for artifacts" >&2
  exit 1
fi

json_str() {
  key="$1"
  data="$2"
  printf '%s' "$data" | tr -d '\n' | sed -n 's/.*"'"${key}"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

abs_url() {
  u="$1"
  u="$(printf '%s' "$u" | sed 's#\\/#/#g')"
  case "$u" in
    http://*|https://*) printf '%s' "$u" ;;
    /*) printf '%s%s' "${GITHUB_SERVER_URL:-}" "$u" ;;
    *) printf '%s%s' "$runtime" "$u" ;;
  esac
}

auth_curl() {
  curl -fsSL --header "Authorization: Bearer ${token}" "$@"
}

case "$cmd" in
  upload)
    [ -f "$file" ] || { echo "missing file $file" >&2; exit 1; }
    content_length="$(wc -c < "$file" | tr -d ' ')"
    md5_b64="$(openssl dgst -md5 -binary "$file" | openssl base64 -A)"
    create_json="$(auth_curl -H 'Content-Type: application/json' \
      -X POST --data "{\"Type\":\"actions_storage\",\"Name\":\"${name}\"}" \
      "${api}?api-version=6.0-preview")"
    upload_url="$(abs_url "$(json_str fileContainerResourceUrl "$create_json")")"
    if [ -z "$upload_url" ]; then
      echo "artifact upload URL missing: $create_json" >&2
      exit 1
    fi
    auth_curl \
      -H "x-actions-results-md5: ${md5_b64}" \
      -H "x-tfs-filelength: ${content_length}" \
      -H "content-range: bytes 0-$((content_length - 1))/${content_length}" \
      -X PUT --data-binary "@${file}" \
      "${upload_url}?itemPath=${name}%2F$(basename "$file")" >/dev/null
    auth_curl -X PATCH \
      "${api}?api-version=6.0-preview&artifactName=${name}" >/dev/null
    echo "uploaded $name $file"
    ;;
  download)
    list_json="$(auth_curl "${api}?api-version=6.0-preview")"
    container="$(json_str fileContainerResourceUrl "$list_json")"
    if [ -z "$container" ]; then
      echo "artifact list missing fileContainerResourceUrl: $list_json" >&2
      exit 1
    fi
    container="$(abs_url "$container")"
    sep='?'
    case "$container" in
      *\?*) sep='&' ;;
    esac
    items_json="$(auth_curl "${container}${sep}itemPath=${name}")"
    loc="$(json_str contentLocation "$items_json")"
    if [ -z "$loc" ]; then
      echo "artifact items missing contentLocation: $items_json" >&2
      exit 1
    fi
    loc="$(abs_url "$loc")"
    mkdir -p "$(dirname "$file")"
    auth_curl -o "$file" "$loc"
    echo "downloaded $name -> $file"
    ls -l "$file"
    ;;
  *)
    usage
    ;;
esac
