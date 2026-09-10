#!/usr/bin/env bash
# Fixtures are paraphrased from the real issues that defeated the pre-filter scan.
set -euo pipefail
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT
FILTER="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/triage_filter.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Fixed clock: 2026-07-12T00:00:00Z. Fixtures are dated against it so the 24h
# rule is deterministic.
NOW=1783814400
OLD="2026-07-01T00:00:00Z"   # 11 days old — clears the 24h rule
FRESH="2026-07-11T18:00:00Z" # 6 hours old  — must be dropped
RECENT="2026-07-10T00:00:00Z" # 2 days old  — a claim this fresh is still live
STALE="2026-05-20T00:00:00Z"  # 53 days old — a claim this old is abandoned

printf 'unionlead\ndefactolead\n' > "$tmpdir/maintainers.txt"

# De facto maintainers: authored a large share of the recent merged PRs, but
# GitHub reports them as CONTRIBUTOR (private org membership, or a lead who was
# never added to the org).
#
# Two of them, because containment in the 3c union is an intent and not a
# guarantee: `defactolead` is in the union, `outsidelead` is not. The union ranks
# contributors by ALL-TIME commits, so a lead who joined recently clears 5 of the
# last 20 merged PRs while sitting outside the top 25, and association cannot
# catch them either — under-reported association is why they are in this file.
printf 'defactolead\noutsidelead\n' > "$tmpdir/defacto.txt"

cat > "$tmpdir/issues.json" <<EOF
[
  {"number": 21795, "title": "Graceful stop on an external file marker",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-a"},
     "body": "Thanks, this works today with the public API exactly as you wrote it, and that is by design.",
     "createdAt": "$OLD"}]},

  {"number": 24282, "title": "[BUG] tracing ends up in logs under the gateway",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Thanks for the report. I don't think that this is a bug in this case.",
     "createdAt": "$OLD"}]},

  {"number": 24343, "title": "[BUG] pruner argument is silently ignored",
   "createdAt": "$OLD", "assignees": [{"login": "other-contributor"}], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "This bug report makes sense to me, I've assigned you the issue, feel free to submit a fix!",
     "createdAt": "$OLD"}]},

  {"number": 6726, "title": "[BUG]: conv2d_transpose aborts on the GPU",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-c"},
     "body": "I see the same thing, and have a kinda hacky patch locally that works around it.",
     "createdAt": "$OLD"}]},

  {"number": 901, "title": "[Discussion] Redesign the connector API",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "help wanted"}], "comments": []},

  {"number": 902, "title": "[CI] flaky test", "createdAt": "$OLD", "assignees": [],
   "labels": [{"name": ">test-failure"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "elasticsearchmachine"},
     "body": "muted; routed to the owning team", "createdAt": "$OLD"}]},

  {"number": 903, "title": "Workspace tree omits deep folders",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "body": "Steps to reproduce: nest a folder six levels deep, then open the tree.",
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
     "body": "Good catch — the tree is scanned server-side with a max depth. PRs welcome!",
     "createdAt": "$OLD"}]},

  {"number": 904, "title": "Union lead blessed this one",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "CONTRIBUTOR", "author": {"login": "unionlead"},
     "body": "Confirmed, happy to review a fix.", "createdAt": "$OLD"}]},

  {"number": 927, "title": "De facto lead confirmed this one",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "CONTRIBUTOR", "author": {"login": "defactolead"},
     "body": "Confirmed, I can reproduce this on main.", "createdAt": "$OLD"}]},

  {"number": 928, "title": "De facto lead outside the union confirmed this one",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "CONTRIBUTOR", "author": {"login": "outsidelead"},
     "body": "Confirmed, I can reproduce this on main.", "createdAt": "$OLD"}]},

  {"number": 905, "title": "Too fresh to have been triaged", "createdAt": "$FRESH",
   "assignees": [], "labels": [{"name": "good first issue"}], "comments": []},

  {"number": 906, "title": "Untriaged feature request", "createdAt": "$OLD", "assignees": [],
   "labels": [{"name": "needs-triage"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "randomuser"},
     "body": "+1, I want this too", "createdAt": "$OLD"}]},

  {"number": 907, "title": "Ghost author must not abort the batch",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "NONE", "author": null,
      "body": "comment from a since-deleted account", "createdAt": "$OLD"},
     {"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
      "body": "Reproduced — PRs welcome.", "createdAt": "$OLD"}]},

  {"number": 908, "title": "New models live in acme/successor 🚀", "isPinned": true,
   "createdAt": "$OLD", "assignees": [],
   "labels": [{"name": "documentation"}, {"name": "enhancement"}, {"name": "priority: low"}],
   "comments": []},

  {"number": 909, "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "title": "[Bug]: The vulnerability I submitted according to your security policy has not received a response",
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Sorry for the delay, we are looking at the report.", "createdAt": "$OLD"}]},

  {"number": 910, "title": "[Tracking] Q3 umbrella for the storage rewrite",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "kind:task"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Children linked below.", "createdAt": "$OLD"}]},

  {"number": 911, "title": "Path traversal in the upload handler reads files outside the root",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}, {"name": "security"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Confirmed, the join is unsanitised. PR welcome.", "createdAt": "$OLD"}]},

  {"number": 912, "title": "Tokenizer drops a trailing byte on some inputs",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Thanks — this should have fixed it in tokenizers v0.23.1, can you retry?",
     "createdAt": "$OLD"}]},

  {"number": 913, "title": "[v4] Loader raises on a valid checkpoint",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "We can't fix bugs on v4 — please upgrade to v5.", "createdAt": "$OLD"}]},

  {"number": 914, "title": "Indexer produces incomplete examples for one doc format",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
     "body": "Thanks for the report, this is valid. We have noted it on our side and will look into supporting that format.",
     "createdAt": "$OLD"}]},

  {"number": 915, "title": "Batched decode corrupts every row after the first",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "kind:bug"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "eager-newcomer"},
     "body": "Hi! I'd like to work on this issue if it's still available.",
     "createdAt": "$RECENT"}]},

  {"number": 916, "title": "Same claim, long abandoned",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "kind:bug"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "eager-newcomer"},
     "body": "Hi! I'd like to work on this issue if it's still available.",
     "createdAt": "$STALE"}]},

  {"number": 917, "title": "Usage totals are summed across tool-loop calls",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
     "body": "https://example.invalid/acme/repo/pull/1", "createdAt": "$OLD"}]},

  {"number": 918, "title": "Quantized matmul ignores the leading batch dimension",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "cc @maint-c for the quantization path", "createdAt": "$OLD"}]},

  {"number": 919, "title": "Join is unsanitised on the secondary path",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Reproduced on main — the second join has the same defect.",
     "createdAt": "$OLD"}]},

  {"number": 920, "title": "Terse blessing is still a blessing",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "PRs welcome!", "createdAt": "$OLD"}]},

  {"number": 921, "title": "Owning the defect is not claiming the fix",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Thanks — reproduced. The regression is on our side, not in your config.",
     "createdAt": "$OLD"}]},

  {"number": 922, "title": "Comment with no timestamp must not abort the batch",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "eager-newcomer"},
      "body": "I would like to work on this."},
     {"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
      "body": "Reproduced, the parser drops the last byte.", "createdAt": "$OLD"}]},

  {"number": 923, "title": "Retry backoff collapses under a slow upstream",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "I can't reproduce this on main. What version are you on?",
     "createdAt": "$OLD"}]},

  {"number": 924, "title": "One maintainer missed it, another did not",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
      "body": "Unable to reproduce on my machine.", "createdAt": "$OLD"},
     {"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
      "body": "Reproduced on main — the second decode path has the same defect.",
      "createdAt": "$OLD"}]},

  {"number": 925, "title": "Asking about an issue is not claiming it",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "kind:bug"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "curious-passerby"},
     "body": "Can I take a look at this? Curious what the root cause is.",
     "createdAt": "$RECENT"}]},

  {"number": 926, "title": "An anchored claim is still a claim",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "kind:bug"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "eager-newcomer"},
     "body": "Can I pick up this one? Happy to send a patch.",
     "createdAt": "$RECENT"}]},

  {"number": 929, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Your approach makes sense to me.", "createdAt": "$OLD"}]},

  {"number": 930, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "You're right about the proposed design.", "createdAt": "$OLD"}]},

  {"number": 931, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Good catch!", "createdAt": "$OLD"}]},

  {"number": 932, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Nice find.", "createdAt": "$OLD"}]},

  {"number": 933, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Good catch. Reproduced on main; the parser drops the last byte.", "createdAt": "$OLD"}]},

  {"number": 934, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Good catch. PRs welcome!", "createdAt": "$OLD"}]},

  {"number": 935, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Your approach makes sense to me.", "createdAt": "$OLD"},
     {"authorAssociation": "MEMBER", "author": {"login": "maint-1"},
     "body": "Reproduced on main; the parser drops the last byte.", "createdAt": "$OLD"}]},

  {"number": 936, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "  False flag.  ", "createdAt": "$OLD"}]},

  {"number": 937, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Not a false flag.", "createdAt": "$OLD"}]},

  {"number": 938, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "Could this be a false flag?", "createdAt": "$OLD"}]},

  {"number": 939, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "The detector emits false flags.", "createdAt": "$OLD"}]},

  {"number": 940, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "False flag", "createdAt": "$OLD"}]},

  {"number": 941, "title": "Parser drops the last byte",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-0"},
     "body": "I think it makes sense.", "createdAt": "$OLD"}]}
]
EOF

OUT="$tmpdir/out.jsonl"
"$FILTER" --issues "$tmpdir/issues.json" --maintainers "$tmpdir/maintainers.txt" \
  --defacto "$tmpdir/defacto.txt" --now "$NOW" > "$OUT"

verdict() { jq -r --argjson n "$1" 'select(.number == $n) | .verdict' "$OUT"; }
reason()  { jq -r --argjson n "$1" 'select(.number == $n) | .reason'  "$OUT"; }
field()   { jq -r --argjson n "$1" "select(.number == \$n) | .$2" "$OUT"; }

want() { # want <number> <verdict> <label>
  got=$(verdict "$1")
  [ "$got" = "$2" ] || { echo "FAIL #$1 ($3): want $2, got '${got:-<no verdict>}'"; exit 1; }
}
want_reason() { # want_reason <number> <substring>
  case "$(reason "$1")" in
    *"$2"*) ;;
    *) echo "FAIL #$1 reason: want *$2*, got '$(reason "$1")'"; exit 1 ;;
  esac
}
dropped() { # dropped <number> <label> — failed the gate, so no verdict at all
  [ -z "$(verdict "$1")" ] || { echo "FAIL #$1 ($2): must fail the gate, got '$(verdict "$1")'"; exit 1; }
}

# A maintainer saying "by design" / "I don't think this is a bug" IS engagement.
# The triage gate alone cannot tell that apart from approval.
want 21795 SKIP "maintainer declined (by design)"
want_reason 21795 declined
want 24282 SKIP "maintainer declined (not a bug)"
want_reason 24282 declined

# The strongest possible approval comment, attached to work handed to someone else.
want 24343 SKIP "assigned to another contributor"
want_reason 24343 other-contributor

# The maintainer already holds the patch; ours cannot land.
want 6726 SKIP "maintainer already fixing it"
want_reason 6726 already

# Apache lazy-consensus trap: an RFC wearing a help-wanted label.
want 901 SKIP "discussion/RFC"
want_reason 901 consensus

# A bot is not a maintainer: its comment must not satisfy the triage gate.
dropped 902 "bot-only triage"

# Controls — these must survive.
want 903 KEEP "genuine bug, maintainer invited a PR"
[ "$(field 903 maintainer_comment_assoc)" = "true" ] || { echo "FAIL #903 assoc flag"; exit 1; }

# A union-only lead (comments as CONTRIBUTOR) still passes the gate but earns no
# approval. The distinction PR #25 drew must survive this change.
want 904 KEEP "union-only maintainer"
[ "$(field 904 maintainer_commented)" = "true" ]      || { echo "FAIL #904 union flag"; exit 1; }
[ "$(field 904 maintainer_comment_assoc)" = "false" ] || { echo "FAIL #904 must not claim approval"; exit 1; }

# Pre-existing gates still hold.
dropped 905 "under 24h old"
dropped 906 "needs-triage only, no maintainer"

# A deleted account serializes as author: null, and `null | test(...)` throws —
# one ghost comment aborted the entire batch, taking every other issue with it.
want 907 KEEP "ghost author does not abort the batch"

# A pinned "this repo moved" notice carries a maintainer taxonomy label, so the
# triage gate blesses it. It is a notice, not a defect: nothing to patch.
want 908 SKIP "pinned announcement"
want_reason 908 pinned

# A complaint about an unanswered security report is labelled `bug` and answered
# by a MEMBER — every approval signal, no defect described.
want 909 SKIP "security-report process complaint"
want_reason 909 advisory

# Tracking/umbrella issues are containers for other work.
want 910 SKIP "tracking/umbrella"
want_reason 910 meta

# Control: a real vulnerability with a patchable root cause must survive. The
# security guard keys on report-process language, not on the word "security".
want 911 KEEP "genuine security bug is still a candidate"

# A fix is as often announced as promised: "should have fixed it in vX" names a
# dead issue, and `already fixed in` does not match that phrasing.
want 912 SKIP "maintainer says the fix already landed"
want_reason 912 "already fixing"

# A refusal is also a decline: "we can.t fix bugs on v4" closes the door as firmly
# as "wontfix".
want 913 SKIP "maintainer declined in the negative"
want_reason 913 "declined"

# Config errors must exit 10, never a verdict code. A config error applies to
# every issue equally, so a verdict-shaped exit empties the candidate set while
# looking like a clean run.
for args in "--issues" "--bogus x" "--maintainers $tmpdir/maintainers.txt"; do
  set +e
  # shellcheck disable=SC2086
  "$FILTER" $args >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" = "10" ] || { echo "FAIL config error '$args' rc: $rc (want 10)"; exit 1; }
done

set +e
"$FILTER" --issues "$tmpdir/nope.json" --maintainers "$tmpdir/maintainers.txt" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL missing issues file rc: $rc (want 10)"; exit 1; }

# --- A KEEP row must carry the issue payload, not just a verdict on a number. ---
#
# The Step-4 rubric scores "is a bug" (title/labels), "has reproduction steps"
# (body), "labeled good-first-issue" (labels) and issue age (createdAt), and the
# agent contract forbids re-fetching any of it. Emit them here or the caller has no
# legal source.
for f in title labels body createdAt; do
  got=$(field 903 "$f")
  [ -n "$got" ] && [ "$got" != "null" ] \
    || { echo "FAIL #903 KEEP row is missing '$f' — the Step-4 rubric cannot score without it"; exit 1; }
done

case "$(field 903 title)" in
  *"Workspace tree omits deep folders"*) ;;
  *) echo "FAIL #903 title did not round-trip: got '$(field 903 title)'"; exit 1 ;;
esac
# Labels arrive normalized to lowercase strings, not {name: …} objects: the shape
# the rubric's good-first-issue / bug tests read.
[ "$(jq -r 'select(.number == 903) | .labels | join(",")' "$OUT")" = "bug" ] \
  || { echo "FAIL #903 labels shape: want [\"bug\"]"; exit 1; }
case "$(field 903 body)" in
  *"Steps to reproduce"*) ;;
  *) echo "FAIL #903 body did not round-trip: got '$(field 903 body)'"; exit 1 ;;
esac

# An issue with no body at all must still emit "" rather than null — the rubric's
# "has reproduction steps" test greps the body, and grepping null is a crash.
[ "$(field 904 body)" = "" ] \
  || { echo "FAIL #904 has no body; want empty string, got '$(field 904 body)'"; exit 1; }

# A SKIP row carries only a reason: it is not a candidate, and a SKIP shaped like a
# KEEP invites the caller to score it.
[ "$(field 21795 title)" = "null" ] \
  || { echo "FAIL #21795 is a SKIP and must not carry a title"; exit 1; }

# A maintainer can confirm a defect and claim it in the same breath. Grading the
# sentiment first scores it as approval and never reaches the claim, so the claim
# test must run before the tiering.
want 914 SKIP "maintainer confirmed it and claimed it"
want_reason 914 already

# A non-maintainer claim is not an assignment, so the assignee test cannot see it.
want 915 SKIP "outside contributor claimed it recently"
want_reason 915 claimed

# ...but a claim nobody acted on must not fence the issue off forever.
want 916 KEEP "stale claim is abandoned, not competing"

# Signal tiers. Association is the prerequisite; the comment text sets the grade.
[ "$(field 903 maintainer_signal)" = "invites_pr" ] || { echo "FAIL #903 signal: got '$(field 903 maintainer_signal)'"; exit 1; }
[ "$(field 911 maintainer_signal)" = "invites_pr" ] || { echo "FAIL #911 signal: got '$(field 911 maintainer_signal)'"; exit 1; }
[ "$(field 919 maintainer_signal)" = "confirms" ]   || { echo "FAIL #919 signal: got '$(field 919 maintainer_signal)'"; exit 1; }
[ "$(field 918 maintainer_signal)" = "neutral" ]    || { echo "FAIL #918 signal: got '$(field 918 maintainer_signal)'"; exit 1; }

# A comment with no prose cannot be graded as prose. A bare link is a pointer,
# not an endorsement, and no sentiment tier can read one.
want 917 KEEP "bare link is not a defect signal"
[ "$(field 917 maintainer_signal)" = "none" ] || { echo "FAIL #917 signal: got '$(field 917 maintainer_signal)'"; exit 1; }

# A union-only lead still earns no signal, whatever they wrote. Commit rank is
# not authority: the 3c union is deliberately wide so the fortress check errs
# toward skipping, and reading endorsement off it would grade any prolific
# committer as a maintainer.
[ "$(field 904 maintainer_signal)" = "none" ] || { echo "FAIL #904 signal: got '$(field 904 maintainer_signal)'"; exit 1; }

# A de facto lead is graded. They are in the union too, so the association-only
# rule above would silently discard the strongest signal the repo has, which is
# how a repo led by a long-term contributor outside the org scores `none` on an
# issue its lead confirmed.
want 927 KEEP "de facto lead confirmed"
[ "$(field 927 maintainer_signal)" = "confirms" ] || { echo "FAIL #927 signal: got '$(field 927 maintainer_signal)'"; exit 1; }
[ "$(field 927 maintainer_comment_assoc)" = "false" ] || { echo "FAIL #927 assoc must stay false"; exit 1; }

# The same lead, outside the union. Grading alone is not enough: the triage gate,
# `maintainer_commented` and `last_maintainer_comment` all read the $mc set, so a
# de facto lead admitted to grading but not to $mc leaves this issue with no
# maintainer comment on record — it fails the gate and never reaches the ranker,
# which is the discard this tier exists to fix. `bug` is deliberately the only
# label: a good-first-issue label would rescue the issue at the gate and hide the
# defect behind a KEEP that reads `maintainer_commented: false` next to
# `maintainer_signal: confirms`.
want 928 KEEP "de facto lead outside the union still counts as a maintainer comment"
[ "$(field 928 maintainer_signal)" = "confirms" ] || { echo "FAIL #928 signal: got '$(field 928 maintainer_signal)'"; exit 1; }
[ "$(field 928 maintainer_commented)" = "true" ] || { echo "FAIL #928 must record a maintainer comment"; exit 1; }
[ "$(field 928 maintainer_comment_assoc)" = "false" ] || { echo "FAIL #928 assoc must stay false"; exit 1; }
[ "$(field 928 last_maintainer_comment)" = "$OLD" ] || { echo "FAIL #928 last_maintainer_comment: got '$(field 928 last_maintainer_comment)'"; exit 1; }

# The strongest signal is also the shortest one anyone writes. A prose floor
# applied before the match would grade this as no signal at all.
want 920 KEEP "terse invite"
[ "$(field 920 maintainer_signal)" = "invites_pr" ] || { echo "FAIL #920 signal: got '$(field 920 maintainer_signal)'"; exit 1; }

# "on our side" attached to the defect owns the bug; attached to the work claims
# it. Only the second is a skip.
want 921 KEEP "maintainer owns the defect without claiming the fix"
[ "$(field 921 maintainer_signal)" = "confirms" ] || { echo "FAIL #921 signal: got '$(field 921 maintainer_signal)'"; exit 1; }

# A comment can serialize without createdAt, and `null | fromdateiso8601` throws,
# which would abort the batch and take every other issue with it.
want 922 KEEP "undated comment does not abort the batch"

# The `reproduc` stem matches its own negation. A maintainer who could not
# reproduce states the opposite of a confirmation and must not be paid +3 for it —
# the exact miscredit this grader exists to stop, one layer down.
want 923 KEEP "failure to reproduce is not a decline"
[ "$(field 923 maintainer_signal)" = "neutral" ] || { echo "FAIL #923 signal: got '$(field 923 maintainer_signal)'"; exit 1; }

# Negations are deleted from the graded text, not short-circuited on: one
# maintainer missing it cannot mute another who reproduced it.
[ "$(field 924 maintainer_signal)" = "confirms" ] || { echo "FAIL #924 signal: got '$(field 924 maintainer_signal)'"; exit 1; }

# "take a look at this" is a question about the issue, not a claim on it. Every
# claim alternative has to anchor on its object or `take` swallows the phrase.
want 925 KEEP "asking about an issue is not claiming it"

# ...and the anchor must not narrow so far that a real claim slips through.
want 926 SKIP "anchored outsider claim still skips"
want_reason 926 claimed

# Generic agreement can endorse someone else's approach without confirming a
# defect (#33). Keep the existing neutral/none floor and independent positives.
for entry in "929 neutral" "930 neutral" "931 none" "932 none" \
             "933 confirms" "934 invites_pr" "935 confirms" "941 neutral"; do
  read -r number expected <<< "$entry"
  want "$number" KEEP "agreement regression/control"
  got=$(field "$number" maintainer_signal)
  [ "$got" = "$expected" ] || { echo "FAIL #$number signal: want $expected, got '$got'"; exit 1; }
done

# Only an entire, unambiguous false-flag dismissal triggers the new decline.
for number in 936 940; do
  want "$number" SKIP "standalone false flag"
  want_reason "$number" declined
done
for number in 937 938 939; do
  want "$number" KEEP "false flag negation/question/description"
  [ "$(field "$number" maintainer_signal)" = "neutral" ] \
    || { echo "FAIL #$number false-flag control signal"; exit 1; }
done

# --defacto is optional, and an absent list must restore association-only
# behaviour exactly — callers predating this tier pass no list at all. Asserted,
# not diffed by hand: the whole tier is opt-in, and an /dev/null default that
# quietly changed a verdict would be a regression nothing else here can see.
OUT_LEGACY="$tmpdir/out_legacy.jsonl"
"$FILTER" --issues "$tmpdir/issues.json" --maintainers "$tmpdir/maintainers.txt" \
  --now "$NOW" > "$OUT_LEGACY"
legacy() { jq -r --argjson n "$1" "select(.number == \$n) | .$2" "$OUT_LEGACY"; }

# 927's author is in the union, so the issue still clears the gate — but with no
# list to lift them past association, the signal they earned above is gone.
[ "$(legacy 927 maintainer_signal)" = "none" ] || { echo "FAIL legacy #927 signal: got '$(legacy 927 maintainer_signal)'"; exit 1; }
# 928's author is in neither set without the list, so the issue is not a
# candidate at all. This is the pre-fix behaviour, reproduced exactly.
[ -z "$(legacy 928 verdict)" ] || { echo "FAIL legacy #928: must fail the gate, got '$(legacy 928 verdict)'"; exit 1; }
# Every issue that does not turn on the de facto tier must be byte-identical.
diff <(grep -Ev '"number":(927|928)[,}]' "$OUT") \
     <(grep -Ev '"number":(927|928)[,}]' "$OUT_LEGACY") \
  || { echo "FAIL: --defacto changed a verdict it must not touch"; exit 1; }

echo "OK test_triage_filter.sh"
