#!/usr/bin/env bash
set -euo pipefail

# Hermes runs the commit pinned at build time (HERMES_REF in the Dockerfile).
# AUTO_UPDATE=true pulls upstream's latest main on every start instead. That runs
# unreviewed code as root, so it is off unless you turn it on for a one-off update.
AUTO_UPDATE="${AUTO_UPDATE:-false}"

if [ "$AUTO_UPDATE" = "true" ]; then
  echo "AUTO_UPDATE=true: updating Hermes to upstream main..."
  cd /opt/hermes-agent
  before="$(git rev-parse HEAD)"
  if git fetch --quiet origin main && git checkout --quiet --detach FETCH_HEAD \
      && git submodule update --quiet --init --recursive; then
    if [ "$(git rev-parse HEAD)" != "$before" ]; then
      echo "Updated ${before:0:12} -> $(git rev-parse --short=12 HEAD). Updating dependencies..."
      VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all,messaging,google]" --quiet
      echo "Update complete."
    else
      echo "Already up to date."
    fi
  else
    # Keep running the version that is already installed.
    echo "Update failed; starting the installed version ${before:0:12}." >&2
    git checkout --quiet --detach "$before" || true
  fi
  cd /
fi

hermes dashboard --host 127.0.0.1 --port 9119 --no-open &

exec python /auth_proxy.py
