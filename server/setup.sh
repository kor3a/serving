#!/usr/bin/env bash
#
# One-command setup for the Tensora API.
#
#   ./setup.sh              create the venv, install, migrate, seed
#   ./setup.sh --recreate   delete an existing .venv first
#
# Picks a Python new enough for Django 5.2 rather than whatever `python3`
# happens to be — macOS still ships 3.9, which cannot install it.

set -euo pipefail

cd "$(dirname "$0")"

MIN_MAJOR=3
MIN_MINOR=10
RECREATE=false

for arg in "$@"; do
    case "$arg" in
        --recreate) RECREATE=true ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- interpreter

is_new_enough() {
    "$1" -c "import sys; sys.exit(0 if sys.version_info >= ($MIN_MAJOR, $MIN_MINOR) else 1)" 2>/dev/null
}

find_python() {
    # Newest first, then whatever python3 points at.
    for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
        if command -v "$candidate" >/dev/null 2>&1 && is_new_enough "$candidate"; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

if ! PYTHON=$(find_python); then
    CURRENT=$(python3 --version 2>&1 || echo "not found")
    cat >&2 <<EOF

$(warn "No Python ${MIN_MAJOR}.${MIN_MINOR}+ found. Your python3 is: ${CURRENT}")

Django 5.2 needs Python ${MIN_MAJOR}.${MIN_MINOR} or newer. macOS ships 3.9, so you
need to install a current one. Either:

  brew install python@3.13

or download the installer from https://www.python.org/downloads/macos/

Then run ./setup.sh again.

EOF
    exit 1
fi

say "Using $($PYTHON --version) at $PYTHON"

# ---------------------------------------------------------------- virtualenv

if [ -d .venv ]; then
    if [ "$RECREATE" = true ]; then
        say "Removing the existing .venv"
        rm -rf .venv
    elif ! is_new_enough .venv/bin/python; then
        EXISTING=$(.venv/bin/python --version 2>&1 || echo unknown)
        fail "
The .venv here was built with ${EXISTING}, which is too old.
Re-run with:   ./setup.sh --recreate
"
    else
        say "Reusing the existing .venv"
    fi
fi

if [ ! -d .venv ]; then
    say "Creating .venv"
    "$PYTHON" -m venv .venv
fi

say "Installing dependencies"
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet -r requirements.txt

# ---------------------------------------------------------------- configure

if [ ! -f .env ]; then
    say "Creating .env from .env.example"
    cp .env.example .env
else
    say "Keeping the existing .env"
fi

say "Applying migrations"
.venv/bin/python manage.py migrate --no-input

say "Seeding demo data"
.venv/bin/python manage.py seed_demo

cat <<EOF

$(say "Ready.")

Start the server:

    cd server
    source .venv/bin/activate
    python manage.py runserver

Then set useMockBackend = false in Tensora/App/AppEnvironment.swift and run
the app. Sign in with:

    player@tensora.app / tensora123     (player side)
    shop@tensora.app   / tensora123     (business side)

EOF
