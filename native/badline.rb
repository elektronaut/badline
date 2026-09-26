# frozen_string_literal: true

# The native badline: boots the machine (or attaches the media given) and
# plays it in an SDL2 window. It builds with Spinel only;
# `rake native:build` builds it into tmp/native/badline. See
# native/README.md, and `badline --help` for the options.

require "badline/native"

begin
  options = Badline::Native::Options.parse(ARGV)
rescue Badline::Native::Options::Error => e
  warn "badline: #{e.message}"
  warn "Try 'badline --help' for more information."
  exit 1
end

if options.help?
  puts Badline::Native::Options::HELP
  exit
end

if options.version?
  puts Badline::Native.version
  exit
end

media = options.media
begin
  sid_model = options.sid_model || Badline::Media.sid_model(media.empty? ? nil : media)
  computer = Badline::Computer.new(sid_model:)
  puts Badline::Media.attach(computer, media, autostart: options.autostart?, song: options.song) unless media.empty?
rescue Badline::Storage::SIDFile::FormatError, Badline::Storage::T64::FormatError,
       Badline::Storage::TAP::FormatError, Badline::Storage::CRTFile::FormatError,
       Badline::Cartridge::UnsupportedTypeError => e
  warn "badline: #{media}: #{e.message}"
  exit 1
end
Badline::Native::App.new(computer, frame_limit: options.frames, paced: options.paced?,
                                   screenshot: options.screenshot, sound: options.sound?).run
