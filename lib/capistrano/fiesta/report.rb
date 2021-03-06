Encoding.default_internal = Encoding.default_external = "utf-8"

require "attr_extras/explicit"
require "capistrano/fiesta/announcement"
require "capistrano/fiesta/github"
require "capistrano/fiesta/template"
require "capistrano/fiesta/editor"
require "capistrano/fiesta/logger"
require "capistrano/fiesta/story"
require "capistrano/fiesta/auto_composed_story"
require "capistrano/fiesta/release"
require "capistrano/fiesta/timestamp_normalizer"

module Capistrano
  module Fiesta
    class Report
      extend AttrExtras.mixin
      pattr_initialize :repo, [:last_released_at, :comment, :auto_compose]
      attr_query :auto_compose?

      def announce(config = {})
        return Logger.warn("Announcement blank, nothing posted to Slack") if nothing_to_announce?
        Announcement.new(text, config).post
      end

      def create_release(name = nil)
        return Logger.warn "No new stories, skipping GitHub release" if stories.none?
        Release.new(repo: repo, name: name, stories: stories).post
      end

      def stories
        @_stories ||= fetch_stories
      end

      private

        def fetch_stories
          if auto_compose?
            merged_pull_requests.map { |pr| AutoComposedStory.new(pr) }
          else
            merged_pull_requests.map { |pr| Story.new(pr) }
          end
        end

        def nothing_to_announce?
          stories.none? || text.nil? || text.empty?
        end

        def text
          @_text ||= render_text
        end

        def render_text
          if auto_compose?
            template
          else
            editor.compose
          end
        end

        def editor
          Editor.new(template, comment: comment)
        end

        def template
          Template.new(stories_with_release_notes).render
        end

        def stories_with_release_notes
          stories.find_all(&:release_note)
        end

        def merged_pull_requests
          github.search_issues("base:master repo:#{repo} merged:>#{last_released_at}").items
        rescue Octokit::UnprocessableEntity => e
          Logger.warn "Unable to access GitHub. Message given was: #{e.message}"
          []
        end

        def last_released_at
          if @last_released_at
            TimestampNormalizer.new(@last_released_at).run.iso8601
          end
        end

        def github
          @_github ||= Github.client
        end
    end
  end
end
