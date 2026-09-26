#!/bin/bash
# Prepares a Claude Code on the web container to run `bundle exec rubocop`
# and `bundle exec rspec`. The regression suites need vendor/ and aren't set
# up here.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# ruby-sdl2 builds against the SDL2 headers, as in CI.
if [ ! -f /usr/include/SDL2/SDL.h ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq libsdl2-dev >/dev/null
fi

# The image ships Ruby 3.3 and an rbenv. Install the newest Ruby 4.0.x, as
# CI's ruby-version "4.0" picks, from the prebuilt binaries setup-ruby uses,
# unless a 4.0 is installed already.
export RBENV_ROOT=/opt/rbenv
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
ruby_version=$(rbenv versions --bare | grep -E '^4\.0\.[0-9]+$' | sort -V | tail -1 || true)
if [ -z "$ruby_version" ]; then
  ruby_version=$(curl -fsSL https://raw.githubusercontent.com/ruby/setup-ruby/master/ruby-builder-versions.json |
    ruby -rjson -e 'puts JSON.parse($stdin.read)["ruby"].grep(/\A4\.0\.\d+\z/).max_by { Gem::Version.new(_1) }')
  # The binaries only run from the prefix they were built with, so unpack
  # there and link it into rbenv.
  . /etc/os-release
  prefix="/opt/hostedtoolcache/Ruby/$ruby_version/x64"
  mkdir -p "$prefix"
  if curl -fsSL "https://github.com/ruby/ruby-builder/releases/download/ruby-$ruby_version/ruby-$ruby_version-ubuntu-$VERSION_ID-x64.tar.gz" |
      tar -xz -C "$prefix" --strip-components=1; then
    ln -sfn "$prefix" "$RBENV_ROOT/versions/$ruby_version"
  else
    # No binary for this Ubuntu release: build from source, which takes minutes.
    rm -rf "$prefix"
    git -C "$RBENV_ROOT/plugins/ruby-build" pull --ff-only -q || true
    MAKE_OPTS="-j$(nproc)" rbenv install --skip-existing "$ruby_version"
  fi
fi
rbenv global "$ruby_version"
rbenv rehash

# Put rbenv's shims ahead of /usr/local/bin/ruby for the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export RBENV_ROOT=$RBENV_ROOT"
    echo "export PATH=\"$RBENV_ROOT/bin:$RBENV_ROOT/shims:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi

# Bundler switches to the version Gemfile.lock was bundled with.
bundle install --jobs "$(nproc)"
