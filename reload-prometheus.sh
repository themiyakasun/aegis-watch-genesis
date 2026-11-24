#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

PROM_URL="${PROM_URL:-http://localhost:9090}"
PROM_IMAGE="${PROM_IMAGE:-prom/prometheus:v3.0.0}"
CONFIG_FILE="${CONFIG_FILE:-prometheus.yml}"

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[[ -f "$CONFIG_FILE" ]] || die "$CONFIG_FILE not found"

log "Checking $CONFIG_FILE with promtool..."
if ! docker run --rm --entrypoint promtool -v "$PWD/$CONFIG_FILE:/etc/prometheus/prometheus.yml:ro" "$PROM_IMAGE" check config /etc/prometheus/prometheus.yml; then
	die "Config vlidation failed. Reload aborted, running config untouched."
fi

curl -fsS "$PROM_URL/-/ready" > /dev/null || die "Prometheus is not ready at $PROM_URL"

log "Config valid. Reloading Prometheus..."
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$PROM_URL/-/reload")
[[ "$code" == '200' ]] || die "Reload returned HTTP $code (is --web.enable-lifecycle set?)"

sleep 1
ok=$(curl -fsS "$PROM_URL/api/v1/query" --data-urlencode 'query=prometheus_config_last_reload_successful' | grep -o '"value":\[[^]]*\]' | grep -o '"[01]"' | tr -d '"' || true)
if [[ "$ok" == "1" ]]; then
	log "Reload Successful."
else
	die "Reload was accepted but Prometheus reports it failed. Check docker-logs"
fi
