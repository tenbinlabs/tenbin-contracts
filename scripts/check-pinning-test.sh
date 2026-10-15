#!/usr/bin/env bash
# Fixture test for scripts/check-pinning.sh: builds throwaway repositories and asserts the
# exact findings and exit status, including that a scan that cannot complete fails.
#
# Usage: scripts/check-pinning-test.sh   (CI: `pinning` job in contracts.yaml)
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-pinning.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
digest=sha256:7cc5e35f6567ee8c66d2abb4aab0fd866669e6207c237c3a8f0947a5c7f17092

# expect <name> <repo> <status> <output>: the check, run in <repo>, prints exactly <output>.
expect() {
  local name=$1 repo=$2 status=$3 expected=$4 actual actual_status=0
  actual=$(cd "$repo" && bash "$check" 2>&1) || actual_status=$?
  if [ "$actual_status" != "$status" ] || [ "$actual" != "$expected" ]; then
    echo "FAIL $name: exit $actual_status, expected $status"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

# repo <dir>: an empty git repository with a Bake file naming one target context.
repo() {
  mkdir -p "$1/docker" "$1/.github/workflows"
  git -C "$1" init -q
  cat >"$1/docker/docker-bake.hcl" <<'EOF'
target "svc" {
  contexts = {
    base-ctx   = "target:base"
    remote-ctx = "docker-image://alpine:3"
  }
}
EOF
}

findings="$work/findings"
repo "$findings"
mkdir -p "$findings/docker/svc" "$findings/.github/actions/x"
cat >"$findings/docker/svc/Dockerfile" <<EOF
FROM --platform=\$BUILDPLATFORM ubuntu:25.10@$digest AS build
FROM build AS second
FROM base-ctx
FROM remote-ctx
FROM scratch
FROM node:20-alpine
FROM self AS self
RUN curl -fsSL https://github.com/a/b/releases/download/v1/x.tar.gz \\
    # a comment inside the instruction
    | tar -xz
RUN curl -fsSL -o /tmp/y.zip https://example.com/y.zip \\
    && echo "abc  /tmp/y.zip" | sha256sum -c -
RUN curl -fsSLO https://example.com/one.tar.gz \\
    && curl -fsSLO https://example.com/two.tar.gz \\
    && echo "abc  one.tar.gz" | sha256sum -c -
HEALTHCHECK CMD curl -fsS http://localhost:8080/healthz || exit 1
ADD https://example.com/z.tar.gz /z.tar.gz
ADD --checksum=sha256:abc https://example.com/ok.tar.gz /ok.tar.gz
RUN <<SCRIPT
set -e
curl -fsSL https://github.com/a/b/releases/download/v1/h.tgz -o h.tgz
SCRIPT
RUN curl -fsSL https://example.com/install.sh | sh
RUN curl -fsSL https://dl.k8s.io/release/v1/bin/kubectl -o /k
EOF
cat >"$findings/.github/workflows/w.yml" <<'EOF'
name: w
jobs:
  a:
    runs-on: ubuntu-latest # comment
    strategy:
      matrix:
        os: [macos-latest]
    steps:
      # runs on ubuntu-latest in a comment only
      - run: curl -fsSL https://github.com/a/b/releases/download/v1/one.tgz -o one.tgz
      - name: verified
        run: |
          curl -fsSL https://github.com/a/b/releases/download/v1/two.tgz -o two.tgz
          echo "abc  two.tgz" | sha256sum --check -
      - name: unverified block
        run: |
          curl -fsSL \
            https://github.com/a/b/releases/download/v1/three.tgz -o three.tgz
      - name: api call
        run: curl -fsS https://api.github.com/repos/a/b
      - name: piped
        run: curl -fsSL https://example.com/get.sh | bash
      - uses: actions/checkout@v4 # zizmor: ignore[unpinned-uses]
      - name: last
        run: |
          wget https://github.com/a/b/releases/download/v1/four.deb
EOF
cat >"$findings/.github/actions/x/action.yml" <<'EOF'
runs:
  using: composite
  steps:
    - shell: bash
      run: curl -fsSL https://github.com/a/b/releases/download/v1/five.zip -o five.zip
EOF
cat >"$findings/.github/pinning-exceptions.txt" <<'EOF'
# header
docker/svc/Dockerfile dl.k8s.io/release expires 2027-01-14 excepted download
  .github/workflows/w.yml four.deb expires 2027-01-14 indented entry
.github/workflows/w.yml nothing-matches expires 2027-01-14 stale entry
docker/svc/Dockerfile missing-date reason here
EOF
git -C "$findings" add -A

expect "every finding, exception and malformed entry" "$findings" 1 "$(cat <<'EOF'
::error file=.github/pinning-exceptions.txt,line=5::expected '<path> <text> expires YYYY-MM-DD <reason>'
::error file=docker/svc/Dockerfile,line=4::FROM without @sha256: FROM remote-ctx
::error file=docker/svc/Dockerfile,line=6::FROM without @sha256: FROM node:20-alpine
::error file=docker/svc/Dockerfile,line=7::FROM without @sha256: FROM self AS self
::error file=docker/svc/Dockerfile,line=8::release download without a sha256 check: RUN curl -fsSL https://github.com/a/b/releases/download/v1/x.tar.gz \
::error file=docker/svc/Dockerfile,line=13::release download without a sha256 check: RUN curl -fsSLO https://example.com/one.tar.gz \
::error file=docker/svc/Dockerfile,line=14::release download without a sha256 check: && curl -fsSLO https://example.com/two.tar.gz \
::error file=docker/svc/Dockerfile,line=17::release download without a sha256 check: ADD https://example.com/z.tar.gz /z.tar.gz
::error file=docker/svc/Dockerfile,line=21::release download without a sha256 check: curl -fsSL https://github.com/a/b/releases/download/v1/h.tgz -o h.tgz
::error file=docker/svc/Dockerfile,line=23::download piped to a shell: RUN curl -fsSL https://example.com/install.sh | sh
::error file=.github/actions/x/action.yml,line=5::release download without a sha256 check: run: curl -fsSL https://github.com/a/b/releases/download/v1/five.zip -o five.zip
::error file=.github/workflows/w.yml,line=4::-latest runner label: runs-on: ubuntu-latest # comment
::error file=.github/workflows/w.yml,line=7::-latest runner label: os: [macos-latest]
::error file=.github/workflows/w.yml,line=10::release download without a sha256 check: - run: curl -fsSL https://github.com/a/b/releases/download/v1/one.tgz -o one.tgz
::error file=.github/workflows/w.yml,line=18::release download without a sha256 check: https://github.com/a/b/releases/download/v1/three.tgz -o three.tgz
::error file=.github/workflows/w.yml,line=22::download piped to a shell: run: curl -fsSL https://example.com/get.sh | bash
::error file=.github/workflows/w.yml,line=23::inline zizmor ignore; add a dated entry to .github/zizmor.yml: - uses: actions/checkout@v4 # zizmor: ignore[unpinned-uses]
::error file=.github/pinning-exceptions.txt::unused exception '.github/workflows/w.yml nothing-matches'; remove it
EOF
)"

clean="$work/clean"
repo "$clean"
printf 'FROM ubuntu:25.10@%s\nRUN true\n' "$digest" >"$clean/Dockerfile"
printf 'jobs:\n  a:\n    runs-on: ubuntu-24.04\n' >"$clean/.github/workflows/w.yml"
git -C "$clean" add -A
expect "a pinned repository passes" "$clean" 0 "All images, runner labels, and release downloads are pinned."

# An unreadable Bake file stops the scan on its first read; the check must fail, not pass.
broken="$work/broken"
repo "$broken"
cp "$clean/Dockerfile" "$broken/Dockerfile"
git -C "$broken" add -A
chmod 000 "$broken/docker/docker-bake.hcl"
actual_status=0
last=$(cd "$broken" && bash "$check" 2>/dev/null | tail -n 1) || actual_status=$?
if [ "$actual_status" = 1 ] && [ "$last" = "::error::the pinning scan did not complete, so its findings cannot be trusted" ]; then
  echo "ok   a scan that cannot complete fails"
else
  echo "FAIL a scan that cannot complete fails: exit $actual_status, last line: $last"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || { echo "$failures case(s) failed"; exit 1; }
