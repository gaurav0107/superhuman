#!/usr/bin/env bash
# ai_policy_gate.sh --repo OWNER/REPO [--ref REF] [--dir DIR]
#
# Does this repo's contribution policy forbid AI-generated / AI-assisted PRs?
#   exit 0  = no explicit prohibition found (eligible)
#   exit 6  = explicit no-AI policy; prints `NO_AI_POLICY: REPO — FILE: "sentence"`
#   exit 10 = config error, not a verdict (callers abort, same rule as reputation_gate)
#
# Reads CONTRIBUTING / AI_POLICY / CODE_OF_CONDUCT files from raw.githubusercontent
# (no REST quota), or from a local checkout with --dir. A missing file or failed
# fetch reads as "no policy": the gate only ever skips on text it actually read.
#
# Conservative by design. A hard skip has no appeal, so this fires only on one
# sentence that names AI AND states a prohibition. It does NOT fire on:
#   - disclosure requirements ("disclose AI use", "undisclosed AI PRs are closed"),
#     which superhuman's PR footer already satisfies;
#   - conditional rules ("unless", "low-effort", "without reviewing it");
#   - permissive sentences ("AI tools are fine/welcome/allowed").
# AI terms are word-bounded: a bare substring match once dropped yt-dlp because
# "ai" occurs inside "chains".
set -euo pipefail

EX_CONFIG=10
EX_NO_AI=6

die() { echo "ai_policy_gate.sh: CONFIG ERROR: $*" >&2; exit "$EX_CONFIG"; }

REPO="" REF="HEAD" DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; REPO="$2"; shift 2 ;;
    --ref)  [ $# -ge 2 ] || die "--ref needs a value";  REF="$2";  shift 2 ;;
    --dir)  [ $# -ge 2 ] || die "--dir needs a value";  DIR="$2";  shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done
[ -n "$REPO" ] || die "--repo required"
[ -z "$DIR" ] || [ -d "$DIR" ] || die "--dir not a directory: $DIR"
[ -n "$DIR" ] || command -v curl >/dev/null 2>&1 || die "curl not found"

POLICY_FILES="CONTRIBUTING.md CONTRIBUTING CONTRIBUTING.rst .github/CONTRIBUTING.md docs/CONTRIBUTING.md
AI_POLICY.md AI-POLICY.md AI_POLICY .github/AI_POLICY.md docs/AI_POLICY.md
CODE_OF_CONDUCT.md .github/CODE_OF_CONDUCT.md"

fetch() {  # fetch <path> -> body on stdout, empty if absent
  if [ -n "$DIR" ]; then
    cat "$DIR/$1" 2>/dev/null || true
  else
    curl -sfL --max-time 15 "https://raw.githubusercontent.com/$REPO/$REF/$1" 2>/dev/null || true
  fi
}

# Prints the first prohibiting sentence, if any. Lines are joined into paragraphs
# (list items and headings start a new one), then split into sentences.
find_prohibition() {
  awk '
  BEGIN {
    Q = sprintf("%c", 39)                      # apostrophe: this program is single-quoted
    B = "(^|[^[:alnum:]])"; E = "([^[:alnum:]]|$)"
    AI = B "(ai|llms?|copilot|chatgpt|gpt|genai|generative|language models?|machine[- ]generated)" E
    BAN1 = B "(not|never) (be )?(accept|accepted|accepting|allow|allowed|permit|permitted|welcome|welcomed|take|merge|merged|review|reviewed|consider|considered|tolerate|tolerated|want|use|submit|submitted|send|open|opened)" E
    BAN2 = B "(prohibit|prohibits|prohibited|forbid|forbids|forbidden|ban|bans|banned|disallow|disallows|disallowed|rejected|refused|unacceptable|not acceptable)" E
    BAN3 = B "be closed" E
    BAN4 = B "no (ai|llm|genai|gpt|machine)[- ]?(generated|assisted|written|authored|created|code|contributions?|prs?|pull requests?|patches|submissions)" E
    COND = "disclos|unless|low[- ](quality|effort)|unreviewed|untested|without (first )?(understanding|reviewing|testing|checking|verifying)|not understand|blindly|spam"
    PERMIT = B "((is|are|be) (fine|ok|okay|welcome|welcomed|allowed|permitted|encouraged|acceptable)|we (welcome|encourage)|feel free|you (may|can) use)" E
  }
  function check(para,   n, i, s, raw) {
    n = split(para, sents, /[.!?][[:space:]]+/)
    for (i = 1; i <= n; i++) {
      raw = sents[i]; s = tolower(raw)
      gsub("won" Q "t", "will not", s); gsub("can" Q "t", "can not", s); gsub("n" Q "t", " not", s)
      gsub(/[*_`]/, "", s)                       # markdown emphasis
      if (s !~ AI) continue
      if (s ~ COND || s ~ PERMIT) continue
      if (s ~ BAN1 || s ~ BAN2 || s ~ BAN3 || s ~ BAN4) {
        gsub(/^[[:space:]#>*+-]+|[[:space:]]+$/, "", raw)
        print substr(raw, 1, 240); found = 1; exit
      }
    }
  }
  function flush() { if (buf != "") check(buf); buf = "" }
  /^[[:space:]]*$/ { flush(); next }
  /^[[:space:]]*([-*+#>]|[0-9]+\.)/ { flush() }
  { buf = buf " " $0 }
  END { if (!found) flush() }
  '
}

for f in $POLICY_FILES; do
  # Curly apostrophes to straight ones, so "don’t" and "don't" read the same.
  hit=$(fetch "$f" | LC_ALL=C sed "s/$(printf '\342\200\231')/'/g" | find_prohibition)
  if [ -n "$hit" ]; then
    echo "NO_AI_POLICY: $REPO — $f: \"$hit\""
    exit "$EX_NO_AI"
  fi
done

echo "AI_POLICY_OK: $REPO"
exit 0
