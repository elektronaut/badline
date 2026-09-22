# Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/elektronaut/badline). Everyone participating
is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Getting started

Badline needs SDL2, which is available from most package managers.

```sh
brew install sdl2           # macOS
apt install libsdl2-dev     # Debian/Ubuntu
```

Install the dependencies and run the specs:

```sh
bundle install
bundle exec rspec
```

Specs tagged `:slow` boot the whole machine and are skipped by default.
Run them with `bundle exec rspec --tag slow`.

The CPU is verified separately against the
[65x02 single step tests](https://github.com/SingleStepTests/65x02).
`rake test` checks the fixtures out into `vendor/65x02` first, which
takes a moment the first time:

```sh
bundle exec rake test
```

Check style before pushing:

```sh
bundle exec rubocop
```

## Pull requests

- Add tests for any behavior you change.
- Write commit messages using
  [Conventional Commits](https://www.conventionalcommits.org). The
  changelog and releases are generated from them, so the `feat:` and
  `fix:` prefixes decide what ends up in the next release.
- Leave the version and `CHANGELOG.md` alone. Both are updated
  automatically when a release is cut.
