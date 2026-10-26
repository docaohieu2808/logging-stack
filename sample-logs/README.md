Sample inputs mounted into the shippers. `docker-json/` is read by the Logstash
`file` input (Docker json-file format: `{"log":"...\n","stream":"stdout","time":"..."}`).
`scripts/smoke-test.sh` appends a uniquely tagged line to `docker-json/0123456789ab-json.log`.
