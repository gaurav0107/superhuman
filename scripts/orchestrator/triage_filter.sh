#!/usr/bin/env bash
# Stage-A issue triage filter (repo-finder Step 4).
#
# Reads the bulk `gh issue list` payload and decides, with no further API calls,
# which issues are worth ranking. Emits, per issue that clears the age and
# triage-signal gates:
#
#   {"verdict":"KEEP","number":N,"title":"…","labels":["bug"],"body":"…",
#    "createdAt":"ISO8601","maintainer_commented":bool,
#    "maintainer_comment_assoc":bool,"last_maintainer_comment":"ISO8601"|null}
#   {"verdict":"SKIP","number":N,"reason":"..."}
#
# A KEEP row carries the issue payload: the Step-4 rubric scores
# title/labels/body/createdAt and may not re-fetch them.
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

ISSUES="" MAINTAINERS="" DEFACTO="" NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --issues)      [ $# -ge 2 ] || die "--issues needs a value"; ISSUES="$2"; shift 2 ;;
    --maintainers) [ $# -ge 2 ] || die "--maintainers needs a value"; MAINTAINERS="$2"; shift 2 ;;
    --defacto)     [ $# -ge 2 ] || die "--defacto needs a value"; DEFACTO="$2"; shift 2 ;;
    --now)         [ $# -ge 2 ] || die "--now needs a value"; NOW="$2"; shift 2 ;;
    *)             die "unknown argument: $1" ;;
  esac
done

[ -n "$ISSUES" ]      || die "--issues is required"
[ -n "$MAINTAINERS" ] || die "--maintainers is required"
[ -f "$ISSUES" ]      || die "issues file not found: $ISSUES"
[ -f "$MAINTAINERS" ] || die "maintainers file not found: $MAINTAINERS"
# Optional: callers predating the de facto tier pass no list, and an absent list
# reads as empty, which restores the association-only behaviour exactly.
[ -n "$DEFACTO" ] && { [ -f "$DEFACTO" ] || die "defacto file not found: $DEFACTO"; }
[ -n "$DEFACTO" ] || DEFACTO=/dev/null
command -v jq >/dev/null 2>&1 || die "jq is required"

# Injectable clock so the 24h rule is testable against a fixed fixture.
NOW="${NOW:-$(date -u +%s)}"
case "$NOW" in (*[!0-9]*) die "--now must be a unix timestamp";; esac

# Regexes use `.` where an apostrophe belongs (don.t, I.ll): this jq program is a
# single-quoted shell string and cannot contain one.
jq -c --rawfile m "$MAINTAINERS" --rawfile d "$DEFACTO" --argjson now "$NOW" '
  ($m | rtrimstr("\n") | split("\n") | map(select(. != ""))) as $maint
  # De facto maintainers: narrower than $maint by intent, admitted to grading
  # because they demonstrably lead the repo. See the caller for how it is built.
  # Narrower by intent is not narrower by construction: $maint ranks contributors
  # by ALL-TIME commits, so a lead who joined recently can clear 5 of the last 20
  # merged PRs and still sit outside the top 25 — and the association legs of
  # $maint cannot catch them either, since under-reported association is the whole
  # reason they are here. So $defacto is unioned into $mc below rather than
  # assumed to be inside it.
  | ($d | rtrimstr("\n") | split("\n") | map(select(. != ""))) as $defacto

  # Bots are not maintainers. Superset of the 3c bot regex: a repo whose CI bot
  # files, labels and comments its own issues yields a perfect triage signal on
  # work no outsider can pick up.
  | "\\[bot\\]$|bot$|machine$|^dependabot|^renovate|^pre-commit-ci|^github-actions" as $bots

  # Engagement is not endorsement: a maintainer explaining why something is not a
  # bug is indistinguishable, to the triage gate, from one blessing it.
  # Parens are load-bearing: `A + B as $x | rest` binds as `A + (B as $x | rest)`,
  # so an unparenthesized concat spills the string into the downstream object
  # stream and jq aborts ("string and object cannot be added") on every issue.
  # A refusal is also a decline: "we cannot fix bugs on v4" closes the door as
  # firmly as "wontfix".
  | ("by design|working as intended|works as intended|not a bug|isn.t a bug"
  + "|don.t think (that )?this is a bug|expected behaviou?r|this is expected"
  + "|won.t fix|wontfix|out of scope|not something we|we don.t plan"
  + "|(can.t|cannot|can not) fix|not (fixing|supporting) (this|that|it)"
  + "|no longer (supported|maintained)|we do not support")                  as $declined

  # A maintainer who already holds the patch will land theirs, not ours. The fix is
  # as often announced as promised, so match both: "should have fixed it in
  # tokenizers v0.23.1" names a dead issue.
  | ("patch locally|i have a (fix|patch)|i.ll (fix|push|open|submit)"
  + "|i.m working on|working on (a fix|this)"
  + "|(already |should have )?fixed (it |this )?in [a-z0-9.@/#-]"
  + "|(fix|patch) (has )?landed|landed in|resolved (in|by) (#|[a-z0-9])"
  + "|(fix|pr) (is )?incoming"
  # A claim is often worded as an intention to act rather than a patch in hand.
  # "this is valid, we will look into it" confirms the defect and takes it in one
  # sentence — which is why the claim test runs before the signal tiering below.
  # "on our side" only claims the work when it is attached to an intent to act:
  # "the regression is on our side" owns the defect and invites a fix.
  + "|we.ll look into|will look into|looking into (this|it) on our"
  + "|noted (it )?(on our side|internally)|taking (this|it) on")             as $claimed

  # An outsider saying "I would like to work on this" is not an assignee, so the
  # assignee test cannot see the claim. Windowed, unlike the maintainer test: a
  # drive-by claim nobody acted on must not fence the issue off forever.
  # Every alternative anchors on its object. Unanchored, `take` swallows "take a
  # look at this" and a question about the issue reads as a claim on it.
  | ("i.d like to work on|i would like to work on"
  + "|can i (take|work on|pick up) (this|it)"
  + "|i.ll (take|work on|pick) (this|it)|assign (this|it) to me"
  + "|i.m (going to |gonna )?work(ing)? on (this|it)"
  + "|(may|could) i (take|work on) (this|it)")                      as $outsider_claim
  | 1209600                                                         as $claim_ttl

  # Association makes a comment gradeable; it does not make it approval. The text
  # sets the grade.
  | ("prs? (are )?welcome|welcome a (pr|patch)|happy to (review|take a pr|accept)"
  + "|feel free to (submit|open|send)|would (accept|welcome) a (pr|patch)"
  + "|go ahead and (open|submit)|contributions? welcome")                 as $invites
  | ("reproduc|confirmed|i see the same|can confirm|this is (valid|a bug|indeed)"
  + "|good catch|you.re right|nice find|makes sense to me")               as $confirms
  # A maintainer who could not reproduce is stating the opposite of a confirmation,
  # and the `reproduc` stem cannot tell the two apart. Not a decline either — the
  # report may still be sound — so these phrases are deleted from the graded text
  # rather than skipped on, leaving the comment to fall to the neutral floor.
  # Deleted, not short-circuited: a second maintainer who did reproduce it must
  # still be able to earn `confirms` on the same issue.
  | ("(can.t|cannot|can not|could ?n.t|could not|unable to|failed to|fails to)"
  + " reproduc\\w*|not reproducible|irreproducible|no repro\\b")          as $no_repro

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
  # $defacto belongs here, not only in $mgrade. This set drives the triage gate,
  # `maintainer_commented` and `last_maintainer_comment`. Grading a de facto lead
  # who is outside $maint while leaving them out of $mc drops the issue at the
  # gate unless a label rescues it — the exact silent discard this tier exists to
  # fix — and any issue that a label does rescue emits the contradiction
  # `maintainer_commented: false` beside `maintainer_signal: confirms`.
  | ($human | map(select(
      (.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))
      or (.author.login as $a | $maint | index($a))
      or (.author.login as $a | $defacto | index($a))
    )))                                                                    as $mc
  | ($human | map(select(
      .authorAssociation | IN("OWNER","MEMBER","COLLABORATOR")
    )))                                                                    as $mca

  # Grading set, deliberately distinct from both sets above. Association is the
  # primary key, but it reports *public* org membership only, so a private member
  # or a lead never added to the org arrives as CONTRIBUTOR and their confirmation
  # is discarded. $defacto restores exactly those. It is not the $maint union:
  # commit rank is not authority, and grading off the union would score any
  # prolific committer as a maintainer, which is the distinction PR #25 drew.
  # $mca stays association-only because maintainer_comment_assoc reports it.
  | ($human | map(select(
      (.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))
      or (.author.login as $a | $defacto | index($a))
    )))                                                                    as $mgrade
  | ($i.labels | map(.name | ascii_downcase))                              as $L
  | ($mc | map(.body // "") | join("\n") | ascii_downcase)                 as $mbody

  # Grade only what is left after stripping links and bare @mentions: a comment
  # that is only a pointer somewhere else states no position on this issue, and no
  # sentiment tier can read one.
  | ($mgrade | map((.body // "")
                | ascii_downcase
                | gsub("https?://\\S+"; " ")
                | gsub("@[a-z0-9_-]+"; " ")
                | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; ""))
          | map(select(length > 0)))                                    as $stripped
  | ($stripped | join("\n"))                                            as $gbody
  | ($gbody | gsub($no_repro; " "))                                     as $gbody_pos
  # Match before measuring. The floor separates a remark from a pointer, so it
  # decides neutral-or-none only — applied first it would grade "PRs welcome!"
  # (12 chars, the strongest signal there is) as no signal at all.
  | (if   ($stripped | length) == 0          then "none"
     elif ($gbody | test($invites))          then "invites_pr"
     elif ($gbody_pos | test($confirms))     then "confirms"
     elif ($stripped | any(length >= 15))    then "neutral"
     else "none" end)                                                   as $signal

  # Non-maintainer claims, still inside the window.
  | ($human | map(select((.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR")) | not))
           # `// ""` is not enough: an undated comment must not reach
           # fromdateiso8601, which throws on null and aborts the whole batch.
           # Undated reads as old, so the claim expires rather than fencing off.
           | map(select(((.body // "") | ascii_downcase | test($outsider_claim))
                        and (((.createdAt // "") | length) > 0)
                        and ((.createdAt | fromdateiso8601) > ($now - $claim_ttl))))
           | length)                                                    as $outsider_live

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
    elif $outsider_live > 0 then
      {verdict: "SKIP", number: $i.number,
       reason: "claimed — another contributor said they are taking it"}
    else
      # Carry the issue payload, not just a verdict on a number. The Step-4 rubric
      # scores title, labels, body and createdAt, and the agent contract forbids
      # re-fetching them — emit them here or the caller has no legal source.
      {verdict: "KEEP", number: $i.number,
       title: $i.title,
       labels: $L,
       body: ($i.body // ""),
       createdAt: $i.createdAt,
       maintainer_commented: ($mc | length > 0),
       maintainer_comment_assoc: ($mca | length > 0),
       maintainer_signal: $signal,
       last_maintainer_comment: ($mc | map(.createdAt) | max)}
    end
' "$ISSUES"
