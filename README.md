# logging-stack

Three logging stacks side-by-side: ELK (Elasticsearch + Logstash + Kibana), Fluentd/Fluent Bit, and Vector. Covers collection, transformation, routing, ILM, and custom plugin authoring.

Useful for interview questions on "compare ELK vs Loki vs Vector" and log pipeline design.

## Tier map

### ELK
| Tier | Path | What it covers |
|------|------|----------------|
| l1 | `elk/l1-basic-elasticsearch-kibana/` | Single-node ES + Kibana compose |
| l2 | `elk/l2-logstash-pipelines/` | Logstash pipelines — Docker JSON + syslog parsing |
| l3 | `elk/l3-index-lifecycle-management/` | ILM policy: hot/warm/cold/delete (30-day retention) |
| l4 | `elk/l4-elasticsearch-cluster/` | 3-node ES cluster compose with TLS |
| l-max | `elk/l-max-custom-logstash-plugin/` | Custom Logstash filter plugin skeleton (Ruby) |

### Fluentd / Fluent Bit
| Tier | Path | What it covers |
|------|------|----------------|
| l1 | `fluentd/l1-basic-forward/` | Basic forward input → stdout |
| l2 | `fluentd/l2-multi-output/` | Multi-output: ES + S3 with buffering |
| l3 | `fluentd/l3-fluent-bit-lightweight/` | Fluent Bit lightweight config (CPU/mem constrained nodes) |
| l-max | `fluentd/l-max-custom-plugin/` | Custom Fluentd output plugin skeleton (Ruby) |

### Vector
| Tier | Path | What it covers |
|------|------|----------------|
| l1 | `vector/l1-basic-pipeline/` | File source → console sink |
| l2 | `vector/l2-transforms-routing/` | Transform + route by log level |
| l3 | `vector/l3-vector-aggregator/` | Aggregator with multiple sources |
| l-max | `vector/l-max-vector-remap-vrl/` | VRL (Vector Remap Language) enrichment transforms |

Full-stack compose (ELK + Fluentd + Vector together): `docker-compose-full-logging.yml`

## Run

```bash
# ELK single-node (quickest start)
docker compose -f elk/l1-basic-elasticsearch-kibana/docker-compose-elk-basic.yml up -d
# Kibana: http://localhost:5601

# Full logging stack
cp .env.example .env   # set ES_PASSWORD, S3_BUCKET etc.
docker compose -f docker-compose-full-logging.yml up -d
```

## Interview talking points

- **ELK vs Loki vs Vector**: ELK indexes full document (high storage, rich query); Loki indexes only labels (low cost, LogQL); Vector is a router/transformer with no storage — can feed either.
- **ILM**: hot (active writes) → warm (read-only, shrink/forcemerge) → cold (low priority) → delete. `freeze` action is a no-op in ES 8.x — cold-tier cost savings now use `searchable_snapshot`.
- **VRL**: functional, sandboxed transform language in Vector — safer than arbitrary Lua/Ruby for prod pipelines.
- **Custom plugins**: both Logstash and Fluentd support Ruby-based plugins; `l-max` shows the skeleton for each.
- **Buffering**: Fluentd l2 shows `<buffer>` with `flush_interval` and `retry_max_times` — prevents log loss on ES downtime.

## Notes

- ILM `freeze` action removed from cold phase (no-op in ES 8.x since 7.x deprecation). See `_note` field in `l3-index-lifecycle-management/ilm-policy-30day-retention.json`.
- All passwords use `${VAR:-default}` pattern; create `.env` before running compose.
