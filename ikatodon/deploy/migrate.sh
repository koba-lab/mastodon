#!/usr/bin/env bash
# Run database migrations for ikatodon from a web server.
#
# Usage: migrate.sh <version> <pre|post>
#
#   pre   run migrations that are safe to apply before the new code is deployed
#         (SKIP_POST_DEPLOYMENT_MIGRATIONS=true), so old and new code can run
#         side by side during the rolling deployment.
#   post  run the remaining (post deployment) migrations once every web server
#         runs the new code.
#
# Environment variables:
#   MASTODON_DIR  directory containing docker-compose.yml (default /home/mastodon/live)
set -euo pipefail

# shellcheck source=ikatodon/deploy/lib.sh
. "$(dirname "$0")/lib.sh"

VERSION="${1:-}"
PHASE="${2:-}"

require_version "$VERSION"
check_environment

# Mastodon treats any non empty SKIP_POST_DEPLOYMENT_MIGRATIONS value as true,
# so the variable must be left unset for the post deployment run.
run_options=(run --rm --no-deps)
case "$PHASE" in
  pre) run_options+=(-e SKIP_POST_DEPLOYMENT_MIGRATIONS=true) ;;
  post) ;;
  *) die 'phase argument must be "pre" or "post"' ;;
esac

# Only interpolate the new image for this one-off container: the long running
# containers are updated by deploy.sh.
export IKATODON_VERSION="$VERSION"

log "pulling image for ${VERSION}"
compose pull --quiet web

log "running ${PHASE} deployment migrations for ${VERSION}"
if ! compose "${run_options[@]}" web bundle exec rails db:migrate; then
  log "${PHASE} deployment migration failed, see the output above for details"
  dump_diagnostics
  die "${PHASE} deployment migration for ${VERSION} failed"
fi

log "${PHASE} deployment migrations for ${VERSION} finished"
