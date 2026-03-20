# encoding: utf-8
# Custom Logstash Filter Plugin Skeleton
# Reference: https://www.elastic.co/guide/en/logstash/current/filter-new-plugin.html
#
# Usage in pipeline config:
#   filter {
#     custom_filter_skeleton {
#       source => "message"
#       target => "enriched"
#       enrich_tags => true
#     }
#   }

require "logstash/filters/base"
require "logstash/namespace"

class LogStash::Filters::CustomFilterSkeleton < LogStash::Filters::Base

  config_name "custom_filter_skeleton"

  # Source field to read from
  config :source, :validate => :string, :default => "message"

  # Target field to write enriched data into
  config :target, :validate => :string, :default => "enriched"

  # Whether to auto-add tags based on content
  config :enrich_tags, :validate => :boolean, :default => false

  # Optional static enrichment fields (key => value pairs)
  config :add_fields_map, :validate => :hash, :default => {}

  public
  def register
    # Initialization: validate config, load external resources, open connections
    @logger.info("CustomFilterSkeleton registered", :source => @source, :target => @target)

    # Example: load a lookup table from file
    # @lookup_table = load_lookup_table("/etc/logstash/lookup.csv")
  end

  public
  def filter(event)
    source_value = event.get(@source)

    return unless source_value

    begin
      enriched = enrich(source_value, event)

      event.set(@target, enriched) if enriched

      # Add static fields from config
      @add_fields_map.each do |field, value|
        event.set(field, value)
      end

      # Auto-tagging based on content
      if @enrich_tags
        apply_tags(source_value, event)
      end

      # Signal successful filter execution
      filter_matched(event)

    rescue => e
      @logger.error("CustomFilterSkeleton error", :exception => e.message, :backtrace => e.backtrace)
      event.tag("_custom_filter_skeleton_failure")
    end
  end

  private

  def enrich(value, event)
    # Core enrichment logic — customize this
    result = {}

    # Example: extract severity from message text
    case value.to_s.downcase
    when /error|exception|fatal/
      result["severity"] = "error"
    when /warn/
      result["severity"] = "warning"
    when /info/
      result["severity"] = "info"
    when /debug/
      result["severity"] = "debug"
    else
      result["severity"] = "unknown"
    end

    # Example: add processing metadata
    result["processed_by"] = "custom_filter_skeleton"
    result["processed_at"] = Time.now.utc.iso8601

    result
  end

  def apply_tags(value, event)
    str = value.to_s.downcase
    event.tag("contains-error")   if str =~ /error|exception/
    event.tag("contains-warning") if str =~ /warn/
    event.tag("slow-request")     if str =~ /took \d{4,}ms/
  end

  # Example helper: load CSV lookup table into hash
  # def load_lookup_table(path)
  #   table = {}
  #   File.readlines(path).each do |line|
  #     key, value = line.strip.split(",", 2)
  #     table[key] = value if key && value
  #   end
  #   table
  # rescue => e
  #   @logger.warn("Could not load lookup table", :path => path, :error => e.message)
  #   {}
  # end
end
