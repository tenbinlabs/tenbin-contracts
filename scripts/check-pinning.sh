#!/usr/bin/env bash
# Fail on an unpinned image base, runner label, or release download.
#
# Usage: scripts/check-pinning.sh   (from anywhere inside the repository)
#
# Checks every tracked Dockerfile, workflow, and composite action for:
#   - a Dockerfile `FROM` without `@sha256:`, unless it names an earlier stage of the same
#     file, `scratch`, or a Bake named context that resolves to a target in
#     docker/docker-bake.hcl when the repository has one;
#   - a `*-latest` runner label in a workflow;
#   - a release download (a URL under `/releases/download/` or `/release/`, or of an archive
#     or package) in a Dockerfile `RUN` / `ADD` (heredoc bodies included) or a `run:` step
#     that has fewer `sha256sum -c` (or `ADD --checksum=sha256:`) checks than release URLs;
#   - a `curl` / `wget` download piped into a shell;
#   - an inline `zizmor: ignore[...]` comment under .github/, whose exceptions belong in
#     .github/zizmor.yml with an expiry date.
# Exceptions are listed in .github/pinning-exceptions.txt, one per line:
#   <path> <text on the offending line, no spaces> expires YYYY-MM-DD <reason>
# The `pinning` job in contracts.yaml fails on a missing or past date.
# scripts/check-pinning-test.sh is the script's own fixture test.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
exceptions_file=.github/pinning-exceptions.txt

# Shared by both awk programs: what a release URL, a checksum check and a pipe into a shell
# look like, and how a step's downloads are reported.
# shellcheck disable=SC2016  # awk program, expanded by awk
awk_common='
  BEGIN {
    url_re = "https?://[^[:space:]\"'\'']*(/releases?/download/|/release/|\\.(tar\\.gz|tgz|tar\\.xz|tar\\.bz2|tar\\.zst|zip|deb|rpm|whl)([^[:alnum:]]|$))"
    check_re = "sha256sum[[:space:]]+(-c|--check)|--checksum=sha256:"
    pipe_re = "(curl|wget)[^|]*[|][[:space:]]*(sudo[[:space:]]+)?(ba|da|z)?sh([[:space:]]|$)"
  }
  function count(s, re,   n) { n = 0; while (match(s, re)) { n++; s = substr(s, RSTART + RLENGTH) } return n }
  function add_line(text,   c) {
    unit = unit " " text
    c = count(text, url_re)
    if (c) { n_urls += c; n_lines++; url_lines[n_lines] = FNR; url_texts[n_lines] = text }
    if (!fetch_line && text ~ /(curl|wget)/) { fetch_line = FNR; fetch_text = text }
  }
  function report(downloader,   i) {
    if (unit ~ downloader && n_urls > count(unit, check_re))
      for (i = 1; i <= n_lines; i++)
        print unit_file "|" url_lines[i] "|release download without a sha256 check|" url_texts[i]
    if (unit ~ pipe_re)
      print unit_file "|" fetch_line "|download piped to a shell|" fetch_text
    unit = ""; n_urls = 0; n_lines = 0; fetch_line = 0
  }
'

# Prints one finding per line: <path>|<line>|<message>|<offending line>. Returns non-zero when
# any part of the scan fails, so a partial scan never reads as a clean one.
scan() {
  local bake_contexts matches grep_status=0
  bake_contexts=""
  if [ -e docker/docker-bake.hcl ]; then
    bake_contexts=$(sed -nE 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*"target:.*/\1/p' \
      docker/docker-bake.hcl | sort -u | tr '\n' ' ') || return 1
  fi

  # shellcheck disable=SC2016  # awk program, expanded by awk
  git ls-files -z -- '*Dockerfile' '*.Dockerfile' '*Dockerfile.*' |
    xargs -0 -r awk -v contexts="$bake_contexts" "$awk_common"'
      function flush() { if (in_unit) report("(curl|wget|^[[:space:]]*ADD[[:space:]])"); in_unit = 0; cont = 0; heredoc = "" }
      FNR == 1 { flush(); delete stages; split(contexts, c, " "); delete known; for (i in c) known[c[i]] = 1 }
      heredoc != "" {
        t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
        if (t == heredoc) flush(); else add_line($0)
        next
      }
      /^[[:space:]]*#/ { next }
      {
        line = $0
        if (!cont) {
          if (toupper($1) == "FROM") {
            image = ""
            for (i = 2; i <= NF; i++) if ($i !~ /^--/) { image = $i; break }
            if (image !~ /@sha256:[0-9a-f]+$/ && !(tolower(image) in stages) && image != "scratch" && !(image in known))
              print FILENAME "|" FNR "|FROM without @sha256|" line
            for (i = 2; i < NF; i++) if (toupper($i) == "AS") stages[tolower($(i + 1))] = 1
          }
          if (toupper($1) == "RUN" || toupper($1) == "ADD") { in_unit = 1; unit_file = FILENAME; unit = "" }
        }
        if (in_unit) {
          add_line(line)
          if (match(line, /<<-?["'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
            heredoc = substr(line, RSTART, RLENGTH); sub(/^<<-?["'\'']?/, "", heredoc)
            next
          }
        }
        cont = (line ~ /\\[[:space:]]*$/)
        if (!cont) flush()
      }
      END { flush() }
    ' || return 1

  # shellcheck disable=SC2016  # awk program, expanded by awk
  git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
    '.github/actions/*action.yml' '.github/actions/*action.yaml' |
    xargs -0 -r awk "$awk_common"'
      function indent(s) { match(s, /^ */); return RLENGTH }
      function flush() { if (in_unit) report("(curl|wget)"); in_unit = 0; in_block = 0 }
      FNR == 1 { flush() }
      {
        line = $0
        code = line; sub(/(^|[[:space:]])#.*/, "", code)
        if (FILENAME ~ /\/workflows\// && code ~ /(ubuntu|windows|macos)-latest/)
          print FILENAME "|" FNR "|-latest runner label|" line
        if (in_block && line !~ /^[[:space:]]*$/ && indent(line) <= block_indent) flush()
        if (match(line, /^[[:space:]]*(- )?run:/)) {
          flush()
          rest = substr(line, RLENGTH + 1)
          block_indent = indent(line) + (line ~ /^[[:space:]]*- / ? 2 : 0)
          in_unit = 1; unit_file = FILENAME; unit = ""
          add_line(line)
          if (rest ~ /^[[:space:]]*[|>]/) in_block = 1; else flush()
        } else if (in_block) {
          add_line(line)
        }
      }
      END { flush() }
    ' || return 1

  # Inline ignores bypass the dated exception list; git grep exits 1 when nothing matches.
  matches=$(git grep -nE 'zizmor:[[:space:]]*ignore\[' -- .github) || grep_status=$?
  [ "$grep_status" -le 1 ] || return 1
  if [ -n "$matches" ]; then
    printf '%s\n' "$matches" |
      awk '{ path = $0; sub(/:.*/, "", path); rest = substr($0, length(path) + 2)
             n = rest; sub(/:.*/, "", n); text = substr(rest, length(n) + 2)
             print path "|" n "|inline zizmor ignore; add a dated entry to .github/zizmor.yml|" text }' ||
      return 1
  fi
}

declare -a exception_path=() exception_text=() exception_used=()
failed=0
if [[ -f "$exceptions_file" ]]; then
  line_number=0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    line_number=$((line_number + 1))
    [[ "$entry" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r path text keyword date _ <<<"$entry"
    if [[ "$keyword" != expires || ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "::error file=$exceptions_file,line=$line_number::expected '<path> <text> expires YYYY-MM-DD <reason>'"
      failed=1
      continue
    fi
    exception_path+=("$path")
    exception_text+=("$text")
    exception_used+=(0)
  done <"$exceptions_file"
fi

findings=$(mktemp)
trap 'rm -f "$findings"' EXIT
if ! scan >"$findings"; then
  echo "::error::the pinning scan did not complete, so its findings cannot be trusted"
  exit 1
fi

while IFS='|' read -r path line message text; do
  excepted=0
  for i in "${!exception_path[@]}"; do
    if [[ "$path" == "${exception_path[$i]}" && "$text" == *"${exception_text[$i]}"* ]]; then
      excepted=1
      exception_used[i]=1
    fi
  done
  if [[ "$excepted" -eq 0 ]]; then
    echo "::error file=$path,line=$line::$message: ${text#"${text%%[![:space:]]*}"}"
    failed=1
  fi
done <"$findings"

for i in "${!exception_path[@]}"; do
  if [[ "${exception_used[$i]}" -eq 0 ]]; then
    echo "::error file=$exceptions_file::unused exception '${exception_path[$i]} ${exception_text[$i]}'; remove it"
    failed=1
  fi
done

if [[ "$failed" -eq 0 ]]; then
  echo "All images, runner labels, and release downloads are pinned."
fi
exit "$failed"
