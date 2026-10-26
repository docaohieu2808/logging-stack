#!/usr/bin/env bash
# End-to-end smoke test: push one uniquely tagged line through each shipper and
# wait until Elasticsearch can search for it.
#
#   scripts/smoke-test.sh elk       # ELK l1-l3: Logstash syslog + docker-json file input + ILM attached
#   scripts/smoke-test.sh shippers  # docker-compose-full-logging.yml: Vector HTTP, Fluent Bit -> Fluentd (normal + error)
#   scripts/smoke-test.sh all       # both (full stack up)
#   ES_URL=https://localhost:9200 ES_CACERT=ca.crt scripts/smoke-test.sh cluster   # l4 TLS cluster
#
# Needs: curl, jq, nc, docker. ELASTIC_PASSWORD from the environment or ./.env.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${ELASTIC_PASSWORD:-}" ] && [ -f "$root/.env" ]; then
  # shellcheck disable=SC1091
  ELASTIC_PASSWORD="$(grep -E '^ELASTIC_PASSWORD=' "$root/.env" | cut -d= -f2-)"
fi
: "${ELASTIC_PASSWORD:?set ELASTIC_PASSWORD or create .env}"
export ELASTIC_PASSWORD
es="${ES_URL:-http://localhost:9200}"
run_id="$(date +%s)$RANDOM"
timeout_s="${SMOKE_TIMEOUT:-180}"

tls=()
[ -n "${ES_CACERT:-}" ] && tls=(--cacert "$ES_CACERT")

es_curl() { curl -sS "${tls[@]}" -u "elastic:${ELASTIC_PASSWORD}" "$@"; }

# wait_for_hit <index-pattern> <token> : poll until a document containing token is searchable
wait_for_hit() {
  local index="$1" token="$2" deadline hits
  deadline=$((SECONDS + timeout_s))
  while [ "$SECONDS" -lt "$deadline" ]; do
    es_curl -o /dev/null -X POST "${es}/${index}/_refresh" 2>/dev/null || true
    hits="$(es_curl -G "${es}/${index}/_search" --data-urlencode "q=\"${token}\"" -d size=0 2>/dev/null \
      | jq -r '.hits.total.value // 0' 2>/dev/null || echo 0)"
    if [ "${hits:-0}" -ge 1 ]; then
      echo "PASS  ${index}  found '${token}'"
      return 0
    fi
    sleep 3
  done
  echo "FAIL  ${index}  '${token}' not searchable after ${timeout_s}s" >&2
  return 1
}

smoke_elk() {
  "$root/elk/l3-index-lifecycle-management/apply-ilm.sh" >/dev/null
  echo "PASS  ILM policy + index template accepted by Elasticsearch"

  local tok="smoke-syslog-${run_id}"
  printf 'Oct 26 10:00:00 smokehost smoketest[1]: %s\n' "$tok" | nc -w1 localhost 5140
  wait_for_hit 'logs-syslog-default' "$tok"

  tok="smoke-dockerjson-${run_id}"
  mkdir -p "$root/sample-logs/docker-json"
  printf '{"log":"{\\"level\\":\\"INFO\\",\\"msg\\":\\"%s\\"}\\n","stream":"stdout","time":"2026-10-26T10:00:00.000000000Z"}\n' \
    "$tok" >> "$root/sample-logs/docker-json/0123456789ab-json.log"
  wait_for_hit 'logs-docker-default' "$tok"

  # the data streams must be managed by our ILM policy
  for ds in logs-syslog-default logs-docker-default; do
    es_curl "${es}/.ds-${ds}-*/_ilm/explain" \
      | jq -e --arg p logs-30day-retention '[.indices[] | select(.managed == true and .policy == $p)] | length >= 1' >/dev/null
    echo "PASS  ${ds} is managed by ILM policy logs-30day-retention"
  done
}

smoke_shippers() {
  local tok="smoke-vector-${run_id}"
  curl -sS --fail-with-body -X POST http://localhost:8080/ingest \
    -H 'Content-Type: application/json' \
    -d "{\"message\":\"${tok}\",\"level\":\"info\",\"host\":\"smoke\"}"
  wait_for_hit 'logs-aggregated-*' "$tok"

  # Fluent Bit tails the Docker json-file log of this container and forwards it to Fluentd
  local normal="smoke-fluentbit-${run_id}" err="smoke-fluentbit-err-${run_id}"
  docker rm -f smoke-emitter >/dev/null 2>&1 || true
  docker run -d --name smoke-emitter alpine:3.22 sh -c \
    "while true; do echo 'hello ${normal}'; echo 'ERROR failed ${err}'; sleep 2; done" >/dev/null
  trap 'docker rm -f smoke-emitter >/dev/null 2>&1 || true' EXIT
  wait_for_hit 'fluentd-2*' "$normal"
  wait_for_hit 'fluentd-errors-*' "$err"
}

smoke_cluster() {
  local nodes tok="smoke-cluster-${run_id}"
  nodes="$(es_curl "${es}/_cat/nodes?h=name" | grep -c '^es0')"
  [ "$nodes" -eq 3 ] || { echo "FAIL  expected 3 nodes, got ${nodes}" >&2; return 1; }
  es_curl "${es}/_cluster/health" | jq -e '.status == "green" and .number_of_nodes == 3' >/dev/null
  echo "PASS  3-node cluster is green"

  # plain HTTP must be refused: TLS is really on
  if curl -sS -o /dev/null --max-time 5 -u "elastic:${ELASTIC_PASSWORD}" "http://${es#https://}/" 2>/dev/null; then
    echo "FAIL  plain HTTP answered on the TLS port" >&2; return 1
  fi
  echo "PASS  plain HTTP is refused, HTTPS with the cluster CA works"

  printf 'Oct 26 10:00:00 smokehost smoketest[1]: %s\n' "$tok" | nc -w1 localhost 5140
  wait_for_hit 'logs-cluster-default' "$tok"
}

case "${1:-all}" in
  elk) smoke_elk ;;
  shippers) smoke_shippers ;;
  cluster) smoke_cluster ;;
  all) smoke_elk; smoke_shippers ;;
  *) echo "usage: $0 [elk|shippers|all|cluster]" >&2; exit 2 ;;
esac
echo "smoke test OK"
