#!/usr/bin/env bash
# Avcheckning M8 – visar allt från GitHub och terminalen i en körning.
# Kör från repots rot: ./scripts/avcheckning.sh   (--no-docker hoppar över compose up)
set -uo pipefail

B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; D=$'\e[2m'; N=$'\e[0m'
h() { # rubrik – väntar på Enter först (inte när utdata går till pipe/fil)
  [[ -t 1 ]] && read -rsp "${D}[Enter] → $1${N}" </dev/tty && printf '\r\e[K'
  printf '\n%s━━ %s ━━%s\n' "$B" "$1" "$N"
}
color() { sed -e "s/success/${G}success${N}/g" -e "s/failure/${R}failure${N}/g" -e "s/skipped/${Y}skipped${N}/g"; }

jobs() { # $1 = run-id
  gh run view "$1" --json jobs --jq '.jobs[] | "  \(.conclusion // .status)\t\(.name)"' | color
}
steps() { # $1 = run-id, $2 = jobbnamn
  gh run view "$1" --json jobs --jq ".jobs[] | select(.name==\"$2\") | .steps[]
    | select(.name | test(\"^(Set up|Complete|Post |Run actions/)\") | not)
    | \"    \(.conclusion // .status)\t\(.name)\"" | color
}
run_id() { # $1 = branch, $2 = conclusion
  gh run list --branch "$1" --workflow ci.yml --json databaseId,conclusion \
    --jq "[.[] | select(.conclusion==\"$2\")][0].databaseId"
}
url() { gh run view "$1" --json url --jq .url; }

# ── GitHub ────────────────────────────────────────────────────────────
h "1. Rött → grönt test (H1) – PR m8-guides"
red=$(run_id m8-guides failure); green=$(run_id m8-guides success)
echo "${R}Röd${N} $(url "$red")"
steps "$red" Integration
echo "  ${D}Felande asserts:${N}"
gh run view "$red" --log-failed 2>/dev/null \
  | grep -o '→ expected.*' | sort -u | sed 's/^/    /'
echo "${G}Grön${N} $(url "$green")"
steps "$green" Integration

h "2. Säkerhet grönt på main"
main=$(gh run list --branch main --workflow ci.yml --event push -L 1 --json databaseId --jq '.[0].databaseId')
echo "$(url "$main")"
jobs "$main"
echo "  ${D}Steg i Säkerhet:${N}"
steps "$main" "Säkerhet"

h "3. Röd PR test-skannern"
gh pr view test-skannern --json number,state,mergedAt,url \
  --jq '"  PR #\(.number) \(.state)  merged: \(.mergedAt // "nej")  \(.url)"'
sk=$(gh run list --branch test-skannern --workflow ci.yml -L 1 --json databaseId --jq '.[0].databaseId')
echo "$(url "$sk")"
steps "$sk" "Säkerhet"

# ── Terminalen ────────────────────────────────────────────────────────
h "4. Headers från compose"
if curl -sf -o /dev/null localhost:3001/api/health; then
  echo "${D}appen kör redan på :3001${N}"
elif [[ "${1:-}" != "--no-docker" ]]; then
  if command -v docker >/dev/null; then dc=(docker compose); else dc=(podman-compose); fi
  echo "${D}${dc[*]} up -d --build …${N}"
  "${dc[@]}" up -d --build >/dev/null 2>&1 || { echo "${R}compose up misslyckades${N}"; exit 1; }
  for _ in $(seq 60); do curl -sf -o /dev/null localhost:3001/api/health && break; sleep 2; done
fi
js=$(curl -s localhost:3001/ | grep -o '/assets/[^"]*\.js' | head -1)
for path in / "$js" /api/health; do
  echo "${B}curl -I localhost:3001$path${N}"
  curl -sI "localhost:3001$path" \
    | grep -iE '^(HTTP|server|content-security-policy|x-content-type-options|cache-control|x-frame-options|referrer-policy)' \
    | sed 's/^/  /'
done
