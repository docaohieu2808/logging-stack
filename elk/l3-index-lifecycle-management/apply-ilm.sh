#!/usr/bin/env bash
# Create the 30-day ILM policy and the index template that attaches it to the
# data streams written by the Logstash pipelines (logs-docker-*, logs-syslog-*).
# Usage: ELASTIC_PASSWORD=... ./apply-ilm.sh   (ES_URL defaults to http://localhost:9200)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
es_url="${ES_URL:-http://localhost:9200}"
auth=(-u "elastic:${ELASTIC_PASSWORD:?set ELASTIC_PASSWORD}")

put() { # put <path> <file>
  curl -sS --fail-with-body "${auth[@]}" -X PUT "${es_url}$1" \
    -H 'Content-Type: application/json' --data-binary "@$2"
  echo
}

put /_ilm/policy/logs-30day-retention "${here}/ilm-policy-30day-retention.json"
put /_index_template/logs-30day-retention "${here}/index-template-logs-30day.json"
