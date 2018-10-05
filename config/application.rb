# frozen_string_literal: true

require_relative "boot"

require "rails/all"
require "csv"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

ENV["FAILBOT_BACKEND"] ||= "memory"

# report exceptions using Failbot
require "failbot_rails"
FailbotRails.setup("classroom#{'-staging' if Rails.env.staging?}")

module GitHubClassroom
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]

    # Available locales
    I18n.available_locales = [:en]

    # Append directories to autoload paths
    config.eager_load_paths += %w[lib].map { |path| Rails.root.join(path).to_s }

    # Configure the generators
    config.generators do |g|
      g.test_framework :rspec, fixture: false
    end

    # GC Profiler for analytics
    GC::Profiler.enable

    # Use SideKiq for background jobs
    config.active_job.queue_adapter = :sidekiq

    # Health checks endpoint for monitoring
    if ENV["PINGLISH_ENABLED"] == "true"
      config.middleware.use Pinglish do |ping|
        ping.check :db do
          ActiveRecord::Base.connection.tables.size
          "ok"
        end

        ping.check :memcached do
          Rails.cache.dalli.checkout.alive!
          "ok"
        end

        ping.check :redis do
          Sidekiq.redis(&:ping)
          "ok"
        end

        ping.check :elasticsearch do
          status = Chewy.client.cluster.health["status"] || "unavailable"

          # Yellow status is when elasticsearch has allocated all of the primary shards,
          # but the replicas have not been allocated. This is okay in our instance since we don't
          # necessarily need replicas.
          # Docs: https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-health.html
          raise "Elasticsearch status is #{status}" unless %w[green yellow].include?(status)
          "ok"
        end

        ping.check :github do
          uri = URI("https://status.github.com/api/status.json")
          status = JSON.parse(Net::HTTP.get(uri))["status"]
          raise "GitHub status is #{status}" unless status == "green"
          "ok"
        end

        ping.check :github_api do
          client = Octokit::Client.new
          client.rate_limit
          status = client.last_response.status
          raise "GitHub API status is #{status}" unless status == 200
          "ok"
        end
      end
    end
  end
end
