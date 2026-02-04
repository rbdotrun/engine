source "https://rubygems.org"

# Specify your gem's dependencies in rbrun.gemspec.
gemspec

gem "puma"

gem "sqlite3"

gem "propshaft"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"

group :development, :test do
  gem "dotenv-rails"
  gem "bullet"
  gem "minitest", "~> 6.0"
end

group :test do
  gem "webmock"
end
