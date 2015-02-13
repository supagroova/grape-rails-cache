require "grape/rails/cache/version"
require "grape/rails/cache/formatter"

module Grape
  module Rails
    module Cache
      extend ActiveSupport::Concern

      included do
        formatter :json, Grape::Rails::Cache::JsonFormatter

        helpers do
          def compare_etag(etag)
            etag = Digest::SHA1.hexdigest(etag.to_s)
            error!("Not Modified", 304) if request.headers["If-None-Match"] == etag

            header "ETag", etag
          end

          # Based on actionpack/lib/action_controller/base.rb, line 1216
          def expires_in(seconds, options = {})
            cache_control = []
            if seconds == 0
              cache_control << "no-cache"
            else
              cache_control << "max-age=#{seconds}"
              if options[:expires_header]
                header 'Expires', seconds.seconds.from_now.httpdate
              end
            end
            if options[:public]
              cache_control << "public"
            else
              cache_control << "private"
            end
            
            options.delete(:expires_header)
            
            # This allows for additional headers to be passed through like 'max-stale' => 5.hours
            cache_control += options.symbolize_keys.reject{|k,v| k == :public || k == :private }.map{ |k,v| v == true ? k.to_s : "#{k.to_s}=#{v.to_s}"}

            header "Cache-Control", cache_control.join(', ')
          end

          def default_expire_time
            2.hours
          end

          def cache(opts = {}, &block)
            # HTTP Cache
            cache_key = opts[:key]

            # Set Cache-Control
            expires_in(
              opts[:expires_in] || default_expire_time, 
              public:           opts.fetch(:public, true), 
              expires_header:   opts.fetch(:expires_header, false) 
            )

            if opts[:etag]
              cache_key += ActiveSupport::Cache.expand_cache_key(opts[:etag])
              compare_etag(opts[:etag]) # Check if client has fresh version
            end

            # Try to fetch from server side cache
            cache_store_expire_time = opts[:cache_store_expires_in] || opts[:expires_in] || default_expire_time
            ::Rails.cache.fetch(cache_key, raw: true, expires_in: cache_store_expire_time) do
              block.call.to_json
            end
          end
        end
      end
    end
  end
end
