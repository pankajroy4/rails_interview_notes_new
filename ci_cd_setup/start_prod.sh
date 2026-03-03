#!/bin/bash

set -e

echo "Installing Gems and Dependencies..."
bundle check || bundle install

# Precompile assets
echo "Precompiling Rails assets..."
bundle exec rails assets:precompile

# Run migrations (optional)
echo "Running database migrations..."
bundle exec rails db:migrate

# Start Puma (or your app server)
echo "Starting Puma..."
exec bundle exec puma -C config/puma.rb
