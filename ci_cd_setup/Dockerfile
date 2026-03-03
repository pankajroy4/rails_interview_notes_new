FROM ruby:3.2.1 AS base

# Install dependencies
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  postgresql-client \
  nodejs \
  libpoppler-dev \
  libimage-exiftool-perl \
  imagemagick \
  libvips42 \
  libvips-dev \
  poppler-utils

WORKDIR /backend

# Install bundler
RUN gem install bundler

# Copy Gemfile separately for caching
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy rest of the app
COPY . .

# Precompile assets
ENV RAILS_ENV=production
ENV RACK_ENV=production

# Expose port
EXPOSE 3000

# Run using Puma (configured in config/puma.rb)
ENTRYPOINT [ "./script/start_prod.sh" ]
