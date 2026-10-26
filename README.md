# logging-stack

[![ci](https://github.com/docaohieu2808/logging-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/docaohieu2808/logging-stack/actions/workflows/ci.yml)

A learning ladder for log pipelines: the ELK stack, Fluentd / Fluent Bit, and Vector. Each level is a
config or compose file you can run, and CI starts the stacks for real on GitHub-hosted runners, sends a
test line through each shipper and checks that Elasticsearch can search for it.

Versions (checked 2026-10-26): Elasticsearch / Kibana / Logstash **8.19.23** (supported until 2027-07-15; 9.x is
the newer line), Fluent Bit **5.1.5**, Fluentd **1.20.1**, Vector **0.60.0**, Prometheus 3.15.1, Grafana 13.2.4.

## Tool status (read this before picking a tool)

| Tool | Status | Use it for |
| --- | --- | --- |
| Elasticsearch / Logstash / Kibana | Maintained by Elastic | Full-text search over logs, rich queries, Kibana UI |
| Fluentd | Maintained (CNCF graduated, 1.20.x), not deprecated. On nodes the community moved to Fluent Bit. | Aggregator with a huge plugin ecosystem (Ruby) |
| Fluent Bit | Maintained, the lightweight successor for node/edge collection | Agent on every host or sidecar (C, tiny footprint) |
| Vector | Maintained (Datadog). 0.60 turned environment-variable interpolation in configs into an opt-in (`VECTOR_DANGEROUSLY_ALLOW_ENV_VAR_INTERPOLATION=true`) | Router/transformer with VRL; no storage of its own |
| Promtail | End of life since 2026-03-02, replaced by Grafana Alloy. Not used here. | - |

## Tier map

### ELK

| Tier | Path | What it covers |
| --- | --- | --- |
| l1 | `elk/l1-basic-elasticsearch-kibana/` | Single-node Elasticsearch + Kibana with security on. A `setup` container sets the `kibana_system` password (without it Kibana gets 401). |
| l2 | `elk/l2-logstash-pipelines/` | Logstash: Docker json-file parsing and syslog parsing, writing to data streams. Compose file builds on l1. |
| l3 | `elk/l3-index-lifecycle-management/` | ILM policy hot / warm / cold / delete (30 days), index template that attaches it to the Logstash data streams, `apply-ilm.sh`. |
| l4 | `elk/l4-elasticsearch-cluster/` | 3-node cluster with real TLS (a one-shot container generates a CA and node certificates, HTTP and transport both encrypted), Logstash and Kibana over HTTPS. |
| l-max | `elk/l-max-custom-logstash-plugin/` | Custom Logstash filter plugin **skeleton** (Ruby). Only syntax-checked in CI, no gemspec or tests. |

### Fluentd / Fluent Bit

| Tier | Path | What it covers |
| --- | --- | --- |
| l1 | `fluentd/l1-basic-forward/` | Fluentd edge agent: forward + syslog + tail inputs, enrichment, shared-key authenticated forward to an aggregator. |
| l2 | `fluentd/l2-multi-output/` | Fluentd aggregator: error tagging with `rewrite_tag_filter`, Elasticsearch (errors and normal indices) and S3 archive, file buffers. |
| l3 | `fluentd/l3-fluent-bit-lightweight/` | Fluent Bit agent tailing Docker logs and forwarding to the Fluentd aggregator. |
| l-max | `fluentd/l-max-custom-plugin/` | Custom Fluentd output plugin **skeleton** (Ruby). Only syntax-checked in CI. |

`fluentd/Dockerfile` builds Fluentd with the three plugins (versions pinned).

### Vector

| Tier | Path | What it covers |
| --- | --- | --- |
| l1 | `vector/l1-basic-pipeline/` | File and Docker sources, VRL JSON parsing, console sink. |
| l2 | `vector/l2-transforms-routing/` | Normalise levels, `route` by level to three Elasticsearch indices, S3 archive. |
| l3 | `vector/l3-vector-aggregator/` | Aggregator: Vector, syslog and HTTP sources, dedupe, throttle, `log_to_metric`, Elasticsearch data stream, S3, Prometheus exporter. |
| l-max | `vector/l-max-vector-remap-vrl/` | Six VRL stages (parse with fallbacks, timestamp, level, HTTP fields, PII redaction, enrichment), dead-letter file sink fed by `reroute_dropped`, and `vector test` unit tests. |

### Whole stack

`docker-compose-full-logging.yml`: one single-node Elasticsearch + Kibana + Logstash (l1/l2), Fluent Bit ->
Fluentd (l3 -> l2) and a Vector aggregator (l3). `--profile metrics` adds Prometheus and Grafana.

## Run it

```bash
cp .env.example .env                      # placeholders, change them

# ELK l1 (Elasticsearch + Kibana):  http://localhost:5601  user elastic / ELASTIC_PASSWORD
docker compose --env-file .env -f elk/l1-basic-elasticsearch-kibana/docker-compose-elk-basic.yml up -d --wait

# ELK l1 + l2 (adds Logstash), then ILM (l3)
docker compose --env-file .env -f elk/l2-logstash-pipelines/docker-compose-logstash.yml up -d --wait
set -a; . ./.env; set +a; elk/l3-index-lifecycle-management/apply-ilm.sh
printf 'Oct 26 10:00:00 myhost app[1]: hello\n' | nc -w1 localhost 5140   # then search logs-syslog-default in Kibana

# ELK l4 (3 nodes, TLS, about 3 GB RAM)
docker compose --env-file .env -f elk/l4-elasticsearch-cluster/docker-compose-elk-3node-cluster.yml up -d --wait
docker cp es01:/usr/share/elasticsearch/config/certs/ca/ca.crt ./ca.crt
curl --cacert ca.crt -u elastic:"$ELASTIC_PASSWORD" https://localhost:9200/_cat/nodes

# Everything (about 4 GB RAM): ELK + Fluent Bit + Fluentd + Vector
docker compose --env-file .env -f docker-compose-full-logging.yml up -d --build --wait
scripts/smoke-test.sh all                 # one tagged line through every shipper, then search for it

# Config-only levels, no stack needed
docker run --rm -e VECTOR_DANGEROUSLY_ALLOW_ENV_VAR_INTERPOLATION=true -e ELASTIC_PASSWORD=x \
  -v "$PWD/vector:/v:ro" timberio/vector:0.60.0-alpine validate --no-environment /v/l2-transforms-routing/vector-transform-route-by-level.toml
```

Elasticsearch runs with `-Xms512m -Xmx512m` everywhere, so the stacks fit a small laptop or a CI runner.
Ports are published on all interfaces: run the labs on a trusted machine or firewall them.

## What CI checks (`.github/workflows/ci.yml`, push / PR / weekly / manual)

| Job | What runs |
| --- | --- |
| lint | actionlint, shellcheck, yamllint, JSON parse, `ruby -c` on the skeletons, `docker compose config` for every compose file, action pins are real commits |
| vector | `vector validate` on all 4 configs, `vector test` on the l-max VRL unit tests |
| fluent | `fluent-bit --dry-run` (l3), `fluentd --dry-run` for l1 and l2 in the image built from `fluentd/Dockerfile` |
| logstash | `logstash --config.test_and_exit` for each pipeline |
| smoke-elk | l1 + l2 with `docker compose up --wait`, ILM policy and template applied, syslog line and docker-json file line searchable, data streams managed by `logs-30day-retention` |
| smoke-shippers | full stack: a line posted to Vector and a line logged by a container (Fluent Bit -> Fluentd, plus an `ERROR` line landing in the errors index) are searchable |
| smoke-cluster | l4: 3 nodes green, plain HTTP refused, a line through Logstash over HTTPS searchable |

## Honest limits

- Plain HTTP and default `changeme-*` passwords in the single-node labs: lab use only. l4 is the only level with TLS.
- ILM `cold` phase only lowers priority. Real cold-tier savings need `searchable_snapshot`, which needs an Enterprise licence and a snapshot repository, so it is not in the policy. The old `freeze` action no longer exists.
- S3 archiving (Fluentd l2, Vector l2/l3) is configured but not exercised in CI (no AWS account). The Fluentd S3 output has `check_bucket false` so the aggregator starts without AWS access; turn it on with real credentials.
- The Ruby plugin skeletons in `l-max` are templates, not working plugins.
- Fluent Bit reads Docker's `json-file` logs from `/var/lib/docker/containers` as root; the `systemd` input is commented out because it needs the host journal mounted.
- Elasticsearch 8.19 is supported until 2027-07-15. To move to 9.x change the image tags together (Elasticsearch, Kibana, Logstash) and re-run the CI jobs.

## Interview talking points

- **ELK vs Loki vs Vector**: ELK indexes the full document (higher storage, rich queries); Loki indexes only labels (cheap, LogQL); Vector and Fluent Bit are routers/transformers with no storage.
- **ILM and data streams**: write to a data stream, attach the policy through an index template (`index.lifecycle.name`), rollover in hot, shrink/forcemerge in warm, delete at 30 days.
- **kibana_system password**: `ELASTIC_PASSWORD` only sets the `elastic` user; service users need their password set through the security API (done by the `setup` containers here).
- **VRL**: compiled and type-checked at startup, so errors like unhandled fallible calls fail `vector validate` instead of production. Fallible functions are handled with `!`, `val, err =` or `??`.
- **Buffering**: Fluentd file buffers and Vector disk buffers keep events when Elasticsearch is down; `retry_max_times` / `when_full` decide what gives first.
- **Fluentd vs Fluent Bit**: same family, Fluent Bit (C, about 1 MB) on every node, Fluentd (Ruby plugins) as the aggregator.
