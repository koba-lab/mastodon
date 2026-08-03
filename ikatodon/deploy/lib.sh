#!/usr/bin/env bash
# Shared helpers for the ikatodon deployment scripts.
# This file is meant to be sourced, not executed.

# Directory holding docker-compose.yml and .env.production on the target host.
MASTODON_DIR="${MASTODON_DIR:-/home/mastodon/live}"
# File used by docker compose for variable interpolation (holds IKATODON_VERSION).
VERSION_ENV_FILE="${VERSION_ENV_FILE:-${MASTODON_DIR}/.env}"
# How long to wait for the containers to become healthy, in seconds.
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

compose() {
  docker compose --project-directory "$MASTODON_DIR" -f "${MASTODON_DIR}/docker-compose.yml" "$@"
}

require_version() {
  local version="${1:-}"
  [ -n "$version" ] || die 'version argument is required (e.g. v4.6.4)'
  case "$version" in
    *[![:alnum:]._-]*) die "invalid version: ${version}" ;;
  esac
}

check_environment() {
  command -v docker >/dev/null 2>&1 || die 'docker is not installed on this host'
  docker compose version >/dev/null 2>&1 || die 'docker compose (v2) is not available on this host'
  [ -d "$MASTODON_DIR" ] || die "MASTODON_DIR does not exist: ${MASTODON_DIR}"
  [ -f "${MASTODON_DIR}/docker-compose.yml" ] || die "docker-compose.yml not found in ${MASTODON_DIR}"
}

# Version currently written in the docker compose env file, if any.
current_version() {
  if [ -f "$VERSION_ENV_FILE" ]; then
    sed -n 's/^IKATODON_VERSION=//p' "$VERSION_ENV_FILE" | tail -n 1
  fi
}

# Persist IKATODON_VERSION so that manual `docker compose` runs on the host use
# the same image as the last deployment.
write_version() {
  local version="$1"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$VERSION_ENV_FILE" ]; then
    grep -v '^IKATODON_VERSION=' "$VERSION_ENV_FILE" >"$tmp" || true
  fi
  printf 'IKATODON_VERSION=%s\n' "$version" >>"$tmp"
  mv "$tmp" "$VERSION_ENV_FILE"
  chmod 0644 "$VERSION_ENV_FILE"
}

# Dump recent container logs so that a failed deployment can be diagnosed from
# the GitHub Actions log without logging into the host.
dump_diagnostics() {
  log '--- docker compose ps ---'
  compose ps || true
  log '--- docker compose logs (last 200 lines) ---'
  compose logs --tail=200 || true
}

http_ok() {
  curl --silent --show-error --fail --max-time 10 --noproxy '*' "$1" >/dev/null
}

# Poll the local web and streaming endpoints until they answer or we time out.
wait_for_health() {
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  local web_url="${WEB_HEALTH_URL:-http://localhost:3000/health}"
  local streaming_url="${STREAMING_HEALTH_URL:-http://localhost:4000/api/v1/streaming/health}"

  while [ "$SECONDS" -lt "$deadline" ]; do
    if http_ok "$web_url" && http_ok "$streaming_url"; then
      log 'health check passed'
      return 0
    fi
    sleep 5
  done

  log "health check did not pass within ${WAIT_TIMEOUT}s"
  return 1
}
