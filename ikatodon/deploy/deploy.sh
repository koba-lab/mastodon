#!/usr/bin/env bash
# Roll out a new ikatodon image on a single web server.
#
# Usage: deploy.sh <version>
#
# Environment variables:
#   MASTODON_DIR  directory containing docker-compose.yml (default /home/mastodon/live)
#   WAIT_TIMEOUT  seconds to wait for the containers to become healthy (default 600)
set -euo pipefail

# shellcheck source=ikatodon/deploy/lib.sh
. "$(dirname "$0")/lib.sh"

VERSION="${1:-}"
require_version "$VERSION"
check_environment

PREVIOUS_VERSION="$(current_version)"
log "deploying ${VERSION} to $(hostname) (current: ${PREVIOUS_VERSION:-unknown})"

export IKATODON_VERSION="$VERSION"

log 'pulling images'
compose pull --quiet web streaming sidekiq

rollback() {
  if [ -z "$PREVIOUS_VERSION" ]; then
    log 'no previous version recorded, skipping rollback'
    return
  fi

  log "rolling back to ${PREVIOUS_VERSION}"
  write_version "$PREVIOUS_VERSION"
  export IKATODON_VERSION="$PREVIOUS_VERSION"
  compose up -d --wait --wait-timeout "$WAIT_TIMEOUT" web streaming sidekiq || log 'rollback failed, manual intervention required'
}

write_version "$VERSION"

# No --remove-orphans: db, redis and es are commented out in docker-compose.yml,
# so it would delete those containers if any of them still exist on the host.
# Recreating only the three services below is all a deployment needs.
if ! compose up -d --wait --wait-timeout "$WAIT_TIMEOUT" web streaming sidekiq; then
  log 'containers did not become healthy'
  dump_diagnostics
  rollback
  die "deployment of ${VERSION} failed"
fi

if ! wait_for_health; then
  dump_diagnostics
  rollback
  die "health check for ${VERSION} failed"
fi

# Remove dangling images so that the VPS does not run out of disk space.
docker image prune --force >/dev/null || true

log "deployed ${VERSION} successfully"
