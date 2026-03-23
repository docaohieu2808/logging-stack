# Logging Stack — ELK + Fluentd + Vector

Legacy grouped repository containing three logging pipeline toolchains: Elasticsearch/Logstash/Kibana (ELK), Fluentd/Fluent Bit, and Vector. Each sub-tool has its own progressive level structure.

## Repository Structure

```
logging-stack/
├── elk/          # Elasticsearch + Logstash + Kibana
├── fluentd/      # Fluentd + Fluent Bit
├── vector/       # Vector (Rust-based pipeline)
└── docker-compose-full-logging.yml   # Full stack: all three together
```

## ELK Stack

| Directory | Level | Covers |
|-----------|-------|--------|
| `elk/l1-basic-elasticsearch-kibana/` | L1 | Single-node ES + Kibana via Docker Compose |
| `elk/l2-logstash-pipelines/` | L2 | Logstash pipeline: grok, mutate, conditional routing |
| `elk/l3-index-lifecycle-management/` | L3 | ILM policies: hot/warm/cold/delete tiers |
| `elk/l4-elasticsearch-cluster/` | L4 | Multi-node ES cluster: shards, replicas, cross-cluster search |
| `elk/l-max-custom-logstash-plugin/` | L-MAX | Custom Logstash Ruby filter plugin |

## Fluentd / Fluent Bit

| Directory | Level | Covers |
|-----------|-------|--------|
| `fluentd/l1-basic-forward/` | L1 | Basic log collection + forward to ES |
| `fluentd/l2-multi-output/` | L2 | Fan-out to multiple outputs (ES, S3, stdout) |
| `fluentd/l3-fluent-bit-lightweight/` | L3 | Fluent Bit as DaemonSet log forwarder to Fluentd aggregator |
| `fluentd/l-max-custom-plugin/` | L-MAX | Custom Fluentd Ruby output plugin |

## Vector

| Directory | Level | Covers |
|-----------|-------|--------|
| `vector/l1-basic-pipeline/` | L1 | Sources → transforms → sinks basic pipeline |
| `vector/l2-transforms-routing/` | L2 | VRL transforms, conditional routing, enrichment |
| `vector/l3-vector-aggregator/` | L3 | Vector as aggregator: batching, compression, backpressure |
| `vector/l-max-vector-remap-vrl/` | L-MAX | Advanced VRL: custom functions, error handling, unit tests |

## Prerequisites

- Docker + Docker Compose
- Kubernetes + `helm` 3.x (for DaemonSet deployments)
- `sysctl vm.max_map_count=524288` (required by Elasticsearch)

## Quick Start

**Full stack (all tools):**
```bash
sudo sysctl -w vm.max_map_count=524288
docker compose -f docker-compose-full-logging.yml up -d
# Kibana: http://localhost:5601
# Elasticsearch: http://localhost:9200
```

**ELK only:**
```bash
docker compose -f elk/l1-basic-elasticsearch-kibana/docker-compose.yml up -d
```

**Vector only:**
```bash
vector --config vector/l1-basic-pipeline/vector.yaml
```

**Fluentd only:**
```bash
docker run --rm \
  -v $(pwd)/fluentd/l1-basic-forward/fluent.conf:/fluentd/etc/fluent.conf \
  fluent/fluentd:v1.16-debian-1
```

## Usage

```bash
# Check Elasticsearch cluster health
curl http://localhost:9200/_cluster/health | jq '.status'

# List indices
curl http://localhost:9200/_cat/indices?v

# Send test log to Logstash (TCP input)
echo '{"level":"info","message":"test","service":"myapp"}' | nc localhost 5000

# Test Vector pipeline
echo '{"message":"hello"}' | vector --config vector/l1-basic-pipeline/vector.yaml

# Fluent Bit DaemonSet on Kubernetes
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  --namespace logging --create-namespace \
  --set backend.type=es \
  --set backend.es.host=elasticsearch.logging.svc.cluster.local
```

## Tool Comparison

| | ELK | Fluentd | Vector |
|---|---|---|---|
| Language | Java / Ruby | Ruby/C | Rust |
| Performance | Medium | Medium | High |
| Memory | High (JVM) | Medium | Low |
| Ecosystem | Huge (plugins) | Large | Growing |
| Best for | Full observability platform | K8s log aggregation | High-throughput pipelines |

## Key Concepts

- **ILM (Index Lifecycle Management)** — automate hot→warm→cold→delete transitions; essential for managing storage costs
- **Fluent Bit + Fluentd pattern** — Fluent Bit as lightweight DaemonSet collector; Fluentd as aggregator with buffering and complex routing
- **VRL (Vector Remap Language)** — safe, expressive language for log transformation; compiled to bytecode at startup
- **Backpressure** — Vector and Fluentd both support buffering and backpressure to survive downstream outages
