# frozen_string_literal: true

module Rbrun
  module Github
    # GitHub API Client
    #
    # Provides REST API access for repository operations.
    class Client < Rbrun::BaseClient
      BASE_URL = "https://api.github.com"

      def initialize(token:)
        @token = token
        raise Error, "GitHub token is required" if @token.blank?
        super()
      end

      # List repositories for the authenticated user.
      def list_repos(sort: "pushed", per_page: 100, page: 1)
        get("/user/repos",
          sort:,
          per_page:,
          page:,
          visibility: "all",
          affiliation: "owner,collaborator,organization_member"
        )
      end

      # Search repositories scoped to the authenticated user.
      def search_repos(query:, per_page: 10)
        scoped_query = "#{query} user:#{username}"
        get("/search/repositories", q: scoped_query, per_page:)
      end

      # Get authenticated user's login name (memoized).
      def username
        @username ||= get("/user")["login"]
      end

      # Get repository details.
      def get_repo(owner:, repo:)
        get("/repos/#{owner}/#{repo}")
      end

      # Get repository contents (file or directory).
      def get_contents(owner:, repo:, path:, ref: nil)
        params = {}
        params[:ref] = ref if ref
        get("/repos/#{owner}/#{repo}/contents/#{path}", params)
      end

      private

        def auth_headers
          {
            "Authorization" => "Bearer #{@token}",
            "Accept" => "application/vnd.github.v3+json"
          }
        end
    end
  end
end
