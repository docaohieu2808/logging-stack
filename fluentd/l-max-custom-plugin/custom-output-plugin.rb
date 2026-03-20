# encoding: utf-8
# Custom Fluentd Output Plugin Skeleton
# Reference: https://docs.fluentd.org/plugin-development/api-plugin-output
#
# Usage in fluent.conf:
#   <match app.**>
#     @type custom_output_plugin
#     endpoint http://my-api.example.com/ingest
#     api_key my-secret-key
#     batch_size 100
#     flush_interval 10s
#   </match>

require "fluent/plugin/output"
require "net/http"
require "uri"
require "json"

module Fluent
  module Plugin
    class CustomOutputPlugin < Output
      Fluent::Plugin.register_output("custom_output_plugin", self)

      # Plugin configuration parameters
      config_param :endpoint,       :string,  desc: "HTTP endpoint to POST log batches to"
      config_param :api_key,        :string,  secret: true, desc: "API key for authentication"
      config_param :batch_size,     :integer, default: 100,  desc: "Max records per HTTP request"
      config_param :connect_timeout,:integer, default: 10,   desc: "HTTP connection timeout in seconds"
      config_param :read_timeout,   :integer, default: 30,   desc: "HTTP read timeout in seconds"
      config_param :include_tag,    :bool,    default: true,  desc: "Include Fluentd tag in payload"
      config_param :include_time,   :bool,    default: true,  desc: "Include event time in payload"

      # Declare buffered output mode
      helpers :formatter

      def configure(conf)
        super
        @uri = URI.parse(@endpoint)
        log.info "CustomOutputPlugin configured", endpoint: @endpoint, batch_size: @batch_size
      end

      def start
        super
        log.info "CustomOutputPlugin started"
      end

      def shutdown
        super
        log.info "CustomOutputPlugin shutdown"
      end

      # write is called with a chunk of buffered events
      def write(chunk)
        records = []

        chunk.each do |time, record|
          entry = record.dup
          entry["_tag"]  = chunk.metadata.tag if @include_tag
          entry["_time"] = Time.at(time).utc.iso8601(3) if @include_time
          records << entry
        end

        # Send in batches
        records.each_slice(@batch_size) do |batch|
          send_batch(batch, chunk.metadata.tag)
        end
      end

      private

      def send_batch(batch, tag)
        payload = JSON.generate({ tag: tag, records: batch, count: batch.size })

        http = Net::HTTP.new(@uri.host, @uri.port)
        http.use_ssl = (@uri.scheme == "https")
        http.open_timeout = @connect_timeout
        http.read_timeout = @read_timeout

        request = Net::HTTP::Post.new(@uri.path.empty? ? "/" : @uri.path)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request["X-Fluentd-Tag"] = tag
        request.body = payload

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "CustomOutputPlugin HTTP error: #{response.code} #{response.message} — #{response.body}"
        end

        log.debug "CustomOutputPlugin batch sent", tag: tag, count: batch.size, status: response.code

      rescue => e
        log.error "CustomOutputPlugin send_batch failed", error: e.message, tag: tag, count: batch.size
        raise # re-raise so Fluentd buffer retries
      end
    end
  end
end
