#!/usr/bin/env bash
set -euo pipefail

label=""
comment=""
repo="${GITHUB_REPOSITORY:-}"
pr_number=""
token="${GITHUB_TOKEN:-}"
event_path="${GITHUB_EVENT_PATH:-}"
json_out=false
dry_run=false

usage() {
  cat <<EOF
Usage: $0 --label NAME --comment PATH [--repo owner/name] [--pr-number N] [--token TOK] [--json] [--dry-run]
Resolves PR number and labels from GITHUB_EVENT_PATH if not provided. If label is present posts comment; otherwise exits non-zero? No, prints outputs for GITHUB_OUTPUT and JSON (optional).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--label) label="$2"; shift 2;;
    -c|--comment) comment="$2"; shift 2;;
    -r|--repo) repo="$2"; shift 2;;
    -n|--pr-number) pr_number="$2"; shift 2;;
    -t|--token) token="$2"; shift 2;;
    --json) json_out=true; shift;;
    --dry-run) dry_run=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

out() {
  local name="$1"; local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  else
    echo "::notice::output $name=$value"
  fi
}

json_escape() { python3 - <<'PY'
import json,sys
s=sys.stdin.read()
print(json.dumps(s)[1:-1])
PY
}

result_posted=false
reason="init"
label_present=false

if [[ -z "$comment" || ! -f "$comment" ]]; then
  echo "warning: comment file not found: $comment" >&2
  out posted false; out reason comment-not-found; out comment_path "$comment"
  $json_out && echo '{"posted":false,"reason":"comment-not-found","comment_path":'"$(printf '%s' "$comment"|json_escape)"'}'
  exit 0
fi

if [[ -z "$label" ]]; then
  echo "error: --label required" >&2; exit 2
fi

resolve_from_event() {
  if [[ -n "$pr_number" ]]; then return 0; fi
  if [[ -f "$event_path" ]]; then
    if command -v jq >/dev/null 2>&1; then
      pr_number=$(jq -r 'if .pull_request then .pull_request.number elif (.issue and .issue.pull_request) then .issue.number else "" end' "$event_path")
      labels=$(jq -r 'if .pull_request then (.pull_request.labels|map(.name)|join(",")) elif (.issue and .issue.labels) then (.issue.labels|map(.name)|join(",")) else "" end' "$event_path")
    else
      read -r pr_number labels < <(python3 - <<'PY'
import json,os,sys
e=json.load(open(os.environ.get('GITHUB_EVENT_PATH',''))) if os.environ.get('GITHUB_EVENT_PATH') else {}
pr=""; labs=[]
if e.get('pull_request'): pr=e['pull_request'].get('number') or ""; labs=[x.get('name') for x in e['pull_request'].get('labels',[])]
elif e.get('issue') and e['issue'].get('pull_request'): pr=e['issue'].get('number') or ""; labs=[x.get('name') for x in e['issue'].get('labels',[])]
print(f"{pr} {';'.join(labs)}")
PY
)
      labels=${labels//;/,}
    fi
    if [[ -n "$labels" ]]; then
      IFS=',' read -r -a arr <<<"$labels"
      for l in "${arr[@]}"; do [[ "$l" == "$label" ]] && label_present=true; done
    fi
  fi
}

resolve_from_event

out label_present "$label_present"

if [[ -z "$pr_number" ]]; then
  echo "warning: PR number not resolved from event; provide --pr-number" >&2
  result_posted=false; reason=no-pr-number
  out posted false; out reason "$reason"; out comment_path "$comment"
  $json_out && printf '{"repo":%s,"pr_number":%s,"label_name":%s,"label_present":%s,"posted":false,"reason":"%s","comment_path":%s,"message_length":%d}\n' \
    "$(printf '%s' "$repo"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "${pr_number:-null}" \
    "$(printf '%s' "$label"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$label_present" \
    "$reason" \
    "$(printf '%s' "$comment"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$(wc -c <"$comment")"
  exit 0
fi

if [[ "$label_present" != true ]]; then
  echo "Label '$label' not present on PR #$pr_number; skipping comment." >&2
  result_posted=false; reason=label-missing
  out posted false; out reason "$reason"; out comment_path "$comment"
  $json_out && printf '{"repo":%s,"pr_number":%s,"label_name":%s,"label_present":false,"posted":false,"reason":"%s","comment_path":%s,"message_length":%d}\n' \
    "$(printf '%s' "$repo"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$pr_number" \
    "$(printf '%s' "$label"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$reason" \
    "$(printf '%s' "$comment"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$(wc -c <"$comment")"
  exit 0
fi

body=$(cat "$comment")
if $dry_run; then
  echo "[dry-run] Would post comment to $repo#$pr_number (len=${#body})"
  result_posted=false; reason=dry-run
  out posted false; out reason "$reason"; out comment_path "$comment"
  $json_out && printf '{"repo":%s,"pr_number":%s,"label_name":%s,"label_present":true,"posted":false,"reason":"%s","comment_path":%s,"message_length":%d}\n' \
    "$(printf '%s' "$repo"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$pr_number" \
    "$(printf '%s' "$label"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$reason" \
    "$(printf '%s' "$comment"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "${#body}"
  exit 0
fi

if [[ -z "$token" ]]; then
  echo "warning: GITHUB_TOKEN not available; cannot post comment" >&2
  result_posted=false; reason=no-token
  out posted false; out reason "$reason"; out comment_path "$comment"
  $json_out && printf '{"repo":%s,"pr_number":%s,"label_name":%s,"label_present":true,"posted":false,"reason":"%s","comment_path":%s,"message_length":%d}\n' \
    "$(printf '%s' "$repo"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$pr_number" \
    "$(printf '%s' "$label"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$reason" \
    "$(printf '%s' "$comment"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "${#body}"
  exit 0
fi

api_url="https://api.github.com/repos/$repo/issues/$pr_number/comments"
resp=$(curl -sSf -X POST -H "Authorization: token $token" -H 'Accept: application/vnd.github+json' -H 'User-Agent: x-cli-ghops' \
  --data-binary @- "$api_url" <<EOF
{"body": $(python3 - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
)}
EOF
)

result_posted=true; reason=ok
out posted true; out reason "$reason"; out comment_path "$comment"
url=$(printf '%s' "$resp" | python3 - <<'PY'
import json,sys
try:
  print(json.load(sys.stdin).get('html_url',''))
except Exception:
  print('')
PY
)

if $json_out; then
  printf '{"repo":%s,"pr_number":%s,"label_name":%s,"label_present":true,"posted":true,"reason":"ok","comment_path":%s,"message_length":%d,"url":%s}\n' \
    "$(printf '%s' "$repo"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$pr_number" \
    "$(printf '%s' "$label"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "$(printf '%s' "$comment"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
    "${#body}" \
    "$(printf '%s' "$url"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')"
fi

