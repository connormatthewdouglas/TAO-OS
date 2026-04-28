#!/usr/bin/env bash
# One-command Linux bootstrap for the CursiveOS Phase 0 seed organism.

set -euo pipefail

REPO_URL="${CURSIVEOS_REPO_URL:-https://github.com/connormatthewdouglas/CursiveOS.git}"
TARGET_DIR="${CURSIVEOS_DIR:-$HOME/CursiveOS}"
BRANCH="${CURSIVEOS_BRANCH:-main}"
VARIANT_PATH="${CURSIVEOS_VARIANT_PATH:-references/seed-organism/variant.example.json}"
CYCLE_ID="${CURSIVEOS_CYCLE_ID:-1}"
SIM_REVENUE_SATS="${CURSIVEOS_SIM_REVENUE_SATS:-100000}"

say() {
  printf '\n[CursiveOS seed] %s\n' "$*"
}

need_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "This seed organism test must run on Linux. This machine reports: $(uname -s)"
    exit 1
  fi
}

install_basic_deps() {
  local missing=()
  command -v git >/dev/null 2>&1 || missing+=("git")
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  command -v curl >/dev/null 2>&1 || missing+=("curl")

  [[ ${#missing[@]} -eq 0 ]] && return 0

  say "Installing required basics: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${missing[@]}"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "${missing[@]}"
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y "${missing[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "${missing[@]}"
  else
    echo "Could not auto-install ${missing[*]}. Please install git, python3, and curl, then run this command again."
    exit 1
  fi
}

sync_repo() {
  if [[ -d "$TARGET_DIR/.git" ]]; then
    say "Updating existing repo at $TARGET_DIR"
    git -C "$TARGET_DIR" fetch origin "$BRANCH"
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
  else
    say "Cloning CursiveOS into $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
}

run_seed() {
  cd "$TARGET_DIR"
  chmod +x cursiveos-full-test-v1.4.sh tools/seed_organism.py 2>/dev/null || true

  say "Initializing local seed organism state"
  python3 tools/seed_organism.py init

  say "Running real Linux seed organism test"
  python3 tools/seed_organism.py run-variant \
    --variant "$VARIANT_PATH" \
    --execute \
    --cycle-id "$CYCLE_ID"

  say "Closing fake revenue cycle"
  python3 tools/seed_organism.py close-cycle \
    --cycle-id "$CYCLE_ID" \
    --revenue-sats "$SIM_REVENUE_SATS"

  say "Local organism status"
  python3 tools/seed_organism.py status

  say "Uploading seed organism artifacts to CursiveRoot"
  if python3 tools/seed_organism.py upload; then
    say "Seed organism artifacts uploaded to CursiveRoot"
  else
    say "Upload did not complete. Local artifacts are still saved and can be retried with: cd $TARGET_DIR && python3 tools/seed_organism.py upload"
  fi

  say "Finished. Local audit bundles are under $TARGET_DIR/.cursiveos/seed/"
  say "Benchmark logs are under $TARGET_DIR/logs/"
}

need_linux
install_basic_deps
sync_repo
run_seed
