# frozen_string_literal: true

# The native badline: boots the machine (or attaches the media given) and
# plays it in the SDL2 window it shares with badline-ruby, or with
# --headless or --audio-out plays or renders a .sid tune without one. It
# builds with Spinel only; `rake native:build` builds it into
# tmp/native/badline. See native/README.md, and `badline --help` for the
# options.

require "badline/native"

$stdout.sync = true

begin
  options = Badline::Options.parse(ARGV, native: true)
rescue Badline::Options::Error => e
  warn "badline: #{e.message}"
  warn "Try 'badline --help' for more information."
  exit 1
end

if options.help?
  puts options.help
  exit
end

if options.version?
  puts Badline::Native.version
  exit
end

if options.headless?
  Signal.trap("INT") { raise Interrupt }
  exit Badline::Audio::CLI.run(options, sink: Badline::Native::SINK, console: Badline::Native::CONSOLE)
end

exit Badline::Frontend.run(options)
