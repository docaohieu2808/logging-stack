# Fluentd with the output plugins the l1/l2 configs need.
# Fluentd is still maintained (CNCF graduated; v1.20.x); Fluent Bit (l3) is the
# lightweight agent that replaces it on nodes, Fluentd stays useful as an aggregator.
FROM fluent/fluentd:v1.20.1-debian-1.0

USER root
# elasticsearch-ruby 9 sends Elasticsearch-9 compatibility headers that an 8.x server rejects (HTTP 400),
# so the client gem is pinned to the 8.x line before the plugin pulls in "any" version.
RUN gem install --no-document elasticsearch:8.19.3 \
 && gem install --no-document \
      fluent-plugin-elasticsearch:6.0.0 \
      fluent-plugin-s3:1.8.6 \
      fluent-plugin-rewrite-tag-filter:2.4.1 \
 && gem sources --clear-all \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem \
 && mkdir -p /var/log/fluentd/buffer /var/log/app \
 && chown -R fluent:fluent /var/log/fluentd
USER fluent
