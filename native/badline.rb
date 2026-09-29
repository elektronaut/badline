# frozen_string_literal: true

# The native badline: boots the machine (or attaches the media given) and
# plays it in an SDL2 window, or with --headless or --audio-out plays or
# renders a .sid tune without one. It builds with Spinel only;
# `rake native:build` builds it into tmp/native/badline. See
# native/README.md, and `badline --help` for the options.

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

exit Badline::Native::Headless.run(options) if options.headless?

media = options.media_path
begin
  sid_model = options.sid_model || Badline::Media.sid_model(media)
  computer = Badline::Computer.new(sid_model:, reu: options.reu,
                                   region: options.ntsc? ? Badline::Region::NTSC : Badline::Region::PAL)
  Badline::Media::TrueDrive.plug(computer) if options.true_drive?
  unless media.nil?
    puts Badline::Media.attach(computer, media, autostart: options.autostart?, song: options.song,
                                                disk: { read_only: options.read_only? })
  end
rescue Badline::Media::TrueDrive::Error, Badline::Storage::SIDFile::FormatError, Badline::Storage::T64::FormatError,
       Badline::Storage::TAP::FormatError, Badline::Storage::CRTFile::FormatError,
       Badline::Storage::G64Image::FormatError, Badline::Cartridge::UnsupportedTypeError => e
  warn "badline: #{media}: #{e.message}"
  exit 1
end
Badline::Native::App.new(computer, options).run
