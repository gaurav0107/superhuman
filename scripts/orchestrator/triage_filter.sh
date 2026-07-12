#!/usr/bin/env bash
# Stage-A issue triage filter (repo-finder Step 4).
#
# Reads the bulk `gh issue list` payload and decides, with no further API calls,
# which issues are worth ranking. Emits, per issue that clears the age and
# triage-signal gates:
#
#   {"verdict":"KEEP","number":N,"maintainer_commented":bool,
#    "maintainer_comment_assoc":bool,"last_maintainer_comment":"ISO8601"|null}
#   {"verdict":"SKIP","number":N,"reason":"..."}
#
# Issues that fail those two gates produce no output at all — they are not
# candidates. Everything past them earns an explicit SKIP with a reason, because
# the decline/claimed tests match prose and a heuristic you cannot watch misfire
# is one you cannot tune.
#
# Exit: 0 ok, 10 config error (never a verdict — a config error applies to every
# issue equally, and wearing a verdict's exit code would empty the candidate set
# while looking like a clean run).
set -euo pipefail

die() { echo "FATAL: $*" >&2; exit 10; }

ISSUES="" MAINTAINERS="" NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --issues)      [ $# -ge 2 ] || die "--issues needs a value"; ISSUES="$2"; shift 2 ;;
    --maintainers) [ $# -ge 2 ] || die "--maintainers needs a value"; MAINTAINERS="$2"; shift 2 ;;
    --now)         [ $# -ge 2 ] || die "--now needs a value"; NOW="$2"; shift 2 ;;
    *)             die "unknown argument: $1" ;;
  esac
done

[ -n "$ISSUES" ]      || die "--issues is required"
[ -n "$MAINTAINERS" ] || die "--maintainers is required"
[ -f "$ISSUES" ]      || die "issues file not found: $ISSUES"
[ -f "$MAINTAINERS" ] || die "maintainers file not found: $MAINTAINERS"
command -v jq >/dev/null 2>&1 || die "jq is required"

# Injectable clock so the 24h rule is testable against a fixed fixture.
NOW="${NOW:-$(date -u +%s)}"
case "$NOW" in (*[!0-9]*) die "--now must be a unix timestamp";; esac

# Regexes use `.` where an apostrophe belongs (don.t, I.ll): this jq program is a
# single-quoted shell string and cannot contain one.
jq -c --rawfile m "$MAINTAINERS" --argjson now "$NOW" '
  ($m | rtrimstr("\n") | split("\n") | map(select(. != ""))) as $maint

  # Bots are not maintainers. Superset of the 3c bot regex: a repo whose CI bot
  # files, labels and comments its own issues yields a perfect triage signal on
  # work no outsider can pick up.
  | "\\[bot\\]$|bot$|machine$|^dependabot|^renovate|^pre-commit-ci|^github-actions" as $bots

  # Engagement is not endorsement: a maintainer explaining why something is not a
  # bug is indistinguishable, to the triage gate, from one blessing it.
  # Parens are load-bearing: `A + B as $x | rest` binds as `A + (B as $x | rest)`,
  # so an unparenthesized concat spills the string into the downstream object
  # stream and jq aborts ("string and object cannot be added") on every issue.
  | ("by design|working as intended|works as intended|not a bug|isn.t a bug"
  + "|don.t think (that )?this is a bug|expected behaviou?r|this is expected"
  + "|won.t fix|wontfix|out of scope|not something we|we don.t plan")       as $declined

  # A maintainer who already holds the patch will land theirs, not ours.
  | ("patch locally|i have a (fix|patch)|i.ll (fix|push|open|submit)"
  + "|i.m working on|working on (a fix|this)|already fixed in"
  + "|(fix|pr) (is )?incoming")                                             as $claimed

  # Announcements and containers wear defect labels. A pinned "the project moved"
  # notice earns a maintainer taxonomy label and every engagement signal the gate
  # tests for, and there is still nothing in it to patch.
  | "^\\s*.(announcement|notice|meta|tracking|umbrella|epic|roadmap|question|support)." as $meta
  | "^(announcement|meta|tracking|umbrella|epic|roadmap|question|support)$"  as $metaL

  # A complaint that a security report went unanswered is a process grievance, not
  # a defect: the fix is a maintainer reply. Keyed on report-process language, so a
  # genuine vulnerability with a patchable cause still ranks.
  | ("security (policy|advisory)|vulnerabilit.{0,40}(submitt|report)"
     + "|(submitt|report)ed.{0,40}vulnerabilit")                          as $secproc

  | .[]
  | . as $i
  # `// ""` guards ghost authors: a deleted account serializes as `author: null`,
  # and `null | test(...)` throws, aborting the whole batch.
  | ($i.comments | map(select((.author.login // "") | test($bots) | not))) as $human
  | ($human | map(select(
      (.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))
      or (.author.login as $a | $maint | index($a))
    )))                                                                    as $mc
  | ($human | map(select(
      .authorAssociation | IN("OWNER","MEMBER","COLLABORATOR")
    )))                                                                    as $mca
  | ($i.labels | map(.name | ascii_downcase))                              as $L
  | ($mc | map(.body // "") | join("\n") | ascii_downcase)                 as $mbody

  # (24h rule) an issue younger than a day has not been triaged; racing to it
  # produces noise PRs.
  | select(($i.createdAt | fromdateiso8601) <= ($now - 86400))

  # (triage rule) a non-bot maintainer comment, an explicit help-wanted/gfi
  # label, or a maintainer-applied taxonomy label. needs-triage alone is not one.
  | select(
      ($mc | length > 0)
      or ($L | any(. == "good first issue" or . == "good-first-issue"
                or . == "help wanted"      or . == "help-wanted"))
      or ($L | any(test("^(kind:|type:|priority:|severity:|area:)")))
    )

  | if ($i.assignees | length) > 0 then
      {verdict: "SKIP", number: $i.number,
       reason: "claimed — assigned to \($i.assignees | map(.login) | join(","))"}
    elif ($i.title | test("^\\s*.(discussion|rfc|proposal)."; "i"))
         or ($L | any(test("^(discussion|rfc|proposal)$"))) then
      {verdict: "SKIP", number: $i.number,
       reason: "discussion/RFC — outcome is consensus, not a patch"}
    elif ($i.isPinned // false) then
      {verdict: "SKIP", number: $i.number,
       reason: "pinned announcement — a repo-level notice, not a defect"}
    elif ($i.title | test($meta; "i")) or ($L | any(test($metaL))) then
      {verdict: "SKIP", number: $i.number,
       reason: "meta/tracking — a container for other work, not a patchable defect"}
    elif ($i.title | test($secproc; "i")) then
      {verdict: "SKIP", number: $i.number,
       reason: "security-report process complaint — answered by an advisory, not a PR"}
    elif ($mbody | test($declined)) then
      {verdict: "SKIP", number: $i.number,
       reason: "maintainer declined it"}
    elif ($mbody | test($claimed)) then
      {verdict: "SKIP", number: $i.number,
       reason: "maintainer is already fixing it"}
    else
      {verdict: "KEEP", number: $i.number,
       maintainer_commented: ($mc | length > 0),
       maintainer_comment_assoc: ($mca | length > 0),
       last_maintainer_comment: ($mc | map(.createdAt) | max)}
    end
' "$ISSUES"
