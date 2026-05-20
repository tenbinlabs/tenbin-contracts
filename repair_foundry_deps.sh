#!/usr/bin/env bash
set -euo pipefail

# Script to fix dependency issues with foundry
# IMPORTANT: Tagged releases need to be hardcoded in DEPS and must match foundry.lock
# When updating dependencies, this script should be updated
# This script must live in packages/contracts and be run from packages/contracts.

CONTRACTS_DIR="$(pwd -P)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CONTRACTS_REL="$(git rev-parse --show-prefix)"
CONTRACTS_REL="${CONTRACTS_REL%/}"

LIB_REL="$CONTRACTS_REL/lib"
GITMODULES="$REPO_ROOT/.gitmodules"

# Hard-code your exact dependencies here.
DEPS=(
  "smartcontractkit/chainlink-ccip@tag=solana-v1.6.2"
  "smartcontractkit/chainlink-local@tag=v0.2.9-beta.0"
  "foundry-rs/forge-std@tag=v1.15.0"
  "OpenZeppelin/openzeppelin-contracts@tag=v5.4.0"
  "OpenZeppelin/openzeppelin-contracts-upgradeable@tag=v5.4.0"
  "morpho-org/vault-v2@tag=2025-12-04"
)

echo "Nuking Foundry dependencies under $LIB_REL..."

cd "$REPO_ROOT"

# Deinitialize submodules under packages/contracts/lib, if any are registered.
if [[ -f "$GITMODULES" ]]; then
  while IFS= read -r key; do
    path="$(git config -f "$GITMODULES" --get "$key")"

    case "$path" in
      "$LIB_REL"|"$LIB_REL/"*)
        git submodule deinit -f -- "$path" 2>/dev/null || true
        ;;
    esac
  done < <(git config -f "$GITMODULES" --name-only --get-regexp '^submodule\..*\.path$' || true)
fi

# Remove old gitlinks from the index.
git rm -rf --cached --ignore-unmatch "$LIB_REL" >/dev/null 2>&1 || true

# Remove working tree deps and local submodule metadata.
rm -rf "$REPO_ROOT/$LIB_REL"
rm -rf "$REPO_ROOT/.git/modules/$LIB_REL"

# Remove stale .gitmodules sections for packages/contracts/lib/*
if [[ -f "$GITMODULES" ]]; then
  while IFS= read -r key; do
    path="$(git config -f "$GITMODULES" --get "$key")"

    case "$path" in
      "$LIB_REL"|"$LIB_REL/"*)
        section="${key%.path}"
        echo "Removing stale .gitmodules section: $section"
        git config -f "$GITMODULES" --remove-section "$section" || true
        ;;
    esac
  done < <(git config -f "$GITMODULES" --name-only --get-regexp '^submodule\..*\.path$' || true)

  # Remove .gitmodules if it became empty.
  if [[ ! -s "$GITMODULES" ]]; then
    rm -f "$GITMODULES"
  fi
fi

echo "Reinstalling Foundry dependencies..."

cd "$CONTRACTS_DIR"

# Force Foundry to use this package's config, not any parent foundry.toml.
if [[ -f "$CONTRACTS_DIR/foundry.toml" ]]; then
  export FOUNDRY_CONFIG="$CONTRACTS_DIR/foundry.toml"
fi

for dep in "${DEPS[@]}"; do
  echo "Installing $dep"
  forge install --root "$CONTRACTS_DIR" "$dep"
done

cd "$REPO_ROOT"

# Stage relevant changes.
git add -A -- "$LIB_REL" 2>/dev/null || true
git add -A -- .gitmodules 2>/dev/null || true
git add -A -- "$CONTRACTS_REL/foundry.lock" 2>/dev/null || true
git add -A -- "$CONTRACTS_REL/foundry.toml" 2>/dev/null || true
git add -A -- "$CONTRACTS_REL/remappings.txt" 2>/dev/null || true

cd "$CONTRACTS_DIR"

echo
echo "Done. Review with:"
echo "  git status"
echo
echo 'Then commit with:'
echo '  git commit -m "reinstall foundry dependencies"'