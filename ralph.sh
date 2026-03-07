#!/bin/bash
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

ITERATIONS=10
MODEL=sonnet
LOG=normal

usage() {
  echo "usage: $0 [options]"
  echo "  -n, --iterations N    loops to run (default: $ITERATIONS)"
  echo "  -m, --model MODEL     claude model (default: $MODEL)"
  echo "  -l, --log LEVEL       normal|verbose (default: $LOG)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--iterations) [[ $# -ge 2 ]] || die "--iterations requires a value"; ITERATIONS="$2"; shift 2;;
    -m|--model)      [[ $# -ge 2 ]] || die "--model requires a value";      MODEL="$2";      shift 2;;
    -l|--log)        [[ $# -ge 2 ]] || die "--log requires a value";        LOG="$2";        shift 2;;
    -h|--help)       usage; exit 0;;
    *)               usage >&2; die "unknown argument: $1";;
  esac
done

[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || die "iterations must be a positive integer, got: $ITERATIONS"
[[ "$LOG" =~ ^(normal|verbose)$ ]] || die "log must be normal or verbose, got: $LOG"

# map to a number for clean jq comparisons (>= 2 = verbose)
case "$LOG" in
  normal)  LOG_LEVEL=1;;
  verbose) LOG_LEVEL=2;;
esac

# Adapted from https://www.aihero.dev/getting-started-with-ralph
# @-prefixed paths are resolved by the claude CLI as file context
read -r -d '' PROMPT << 'EOF' || true
@docs/PLAN.md @docs/progress.txt
1. Read PLAN.md. Find the first issue with status READY, or IN PROGRESS if resuming from a failure. If no such issue exists, output <promise>COMPLETE</promise> and stop.
2. Mark the issue IN PROGRESS in PLAN.md when you start, COMPLETE when done.
3. Verify your work, marking acceptance criteria in PLAN.md, and fixing any failures before marking COMPLETE.
4. Append a brief progress note (with timestamp) to docs/progress.txt.
5. Make a git commit scoped to that issue only.
6. If the completed issue was blocking others (e.g. 'Status: BLOCKED by Issue N'), mark those READY in PLAN.md. If no READY issues remain, output <promise>COMPLETE</promise>.
ONLY WORK ON A SINGLE ISSUE. Never work on a BLOCKED issue.
EOF

tmpfile=""
trap 'rm -f "${tmpfile:-}"' EXIT INT TERM

for ((i=1; i<=ITERATIONS; i++)); do
  [[ $i -gt 1 ]] && echo
  echo "━━━ iteration $i / $ITERATIONS started $(date "+%Y-%m-%d %H:%M:%S") ━━━"
  tmpfile=$(mktemp)

  # --output-format stream-json emits one JSON object per line as each event arrives.
  # tee captures the JSONL for the COMPLETE check; jq renders events by log level:
  #   1 normal  → session id, claude text, tool calls  (default)
  #   2 verbose → + tool results
  claude --model "$MODEL" --permission-mode bypassPermissions --output-format stream-json --verbose \
    -p "$PROMPT" \
    | tee "$tmpfile" \
    | jq -rj --unbuffered --argjson log "$LOG_LEVEL" '
      if .type == "system" and .subtype == "init" then
        "session \(.session_id)\n\n"

      elif .type == "assistant" then
        .message.content[]? |
        if .type == "text" then .text + "\n"
        elif .type == "tool_use" then
          .input as $in |
          (.name | if startswith("mcp__") then split("__") | "mcp:\(.[1])/\(.[2:]|join("__"))" else . end) as $label |
          "  [\($label): \($in | to_entries | map(select(.value | type == "string")) | first // {value:"?"} | .value | if length > 80 then .[0:80] + "…" else . end)]\n"
        else empty end

      elif .type == "user" then
        if $log < 2 then empty else
          .message.content[]? | select(.type == "tool_result") |
          (.content | if type == "string" then . elif type == "array" then [.[] | if .type == "text" then .text else "(image)" end] | join("") else "" end) |
          select(startswith("<system-reminder>") | not) |
          gsub("(?m)^ *[0-9]+→"; "") |
          split("\n") | map(select(length > 0)) |
          if length == 0 then empty
          elif length <= 3 then "  → \(join("\n    "))\n"
          else "  → \(.[0:3] | join("\n    "))\n    … (\(length - 3) more lines)\n"
          end
        end

      elif .type == "result" then
        "\nturns=\(.num_turns) cost=$\(.total_cost_usd // 0 | . * 10000 | round / 10000) duration=\(.duration_ms / 1000 | floor)s\n"

      else empty end'

  echo "━━━ iteration $i / $ITERATIONS ended $(date "+%Y-%m-%d %H:%M:%S") ━━━"

  if jq -e 'select(.type == "result") | .result | contains("<promise>COMPLETE</promise>")' "$tmpfile" > /dev/null 2>&1; then
    echo "━━━ complete after $i / $ITERATIONS iterations ━━━"
    exit 0
  fi
  rm -f "$tmpfile"
  tmpfile=""
done

echo "━━━ stopped after $ITERATIONS iterations without COMPLETE ━━━" >&2
