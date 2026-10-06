# frozen_string_literal: true

module Badline
  # The window both builds play the machine in, badline-ruby on CRuby and
  # the native badline compiled with Spinel, so it stays inside the subset
  # of Ruby Spinel compiles. On CRuby, require badline/ffi before it.
  module Frontend
    # Builds the machine the options ask for and plays it in the window
    # until it closes, and returns the exit status: 1 when the media won't
    # attach, an --at key names nothing or an event fails, which it warns
    # about.
    def self.run(options)
      error = Timeline.error(options.timeline)
      unless error.empty?
        warn "#{options.program}: #{error}"
        return 1
      end

      begin
        computer = boot(options)
      rescue Media::TrueDrive::Error, Storage::SIDFile::FormatError, Storage::T64::FormatError,
             Storage::TAP::FormatError, Storage::CRTFile::FormatError, Storage::G64Image::FormatError,
             Cartridge::UnsupportedTypeError, Snapshot::FormatError, Media::DiskList::Error,
             Datasette::Missing, Unsupported => e
        warn "#{options.program}: #{options.media_path}: #{e.message}"
        return 1
      end
      timeline = Timeline.new(options)
      App.new(computer, options, timeline).run
      timeline.failed? ? 1 : 0
    end

    # The machine a .vsf snapshot holds, built as the saved one was, or a
    # new one built from the options with the media attached.
    def self.boot(options)
      media = options.media_path
      if options.snapshot?
        computer = Snapshot.load(media) { |line| puts line }
        puts "Restored #{media}"
        return computer
      end

      start(options, media, options.writable?)
    end

    # A new machine built from the options, with `media`, if not nil,
    # attached and started as the command line does, its disk writable if
    # `writable`. The family and model give the machine, and a .sid tune
    # or --sid the SID. The VIC-20 raises Unsupported for a .sid
    # tune.
    def self.start(options, media, writable)
      computer = options.family == :vic20 ? vic20(options, media) : c64(options, media)
      Media::TrueDrive.plug(computer) if options.true_drive?
      unless media.nil?
        puts Media.attach(computer, media, autostart: options.autostart?, subtune: options.subtune,
                                           disk: { read_only: !writable })
      end
      computer
    end

    def self.c64(options, media)
      sid_model = options.sid_model || Media.sid_model(media, otherwise: nil)
      Machine.build(:c64, model: options.model, sid_model:, reu: options.reu)
    end

    # A VIC-20 with the RAM --ram names, or else the RAM `media` needs
    # (Media::Vic20Media.ram_for), which it says. Raises Unsupported for
    # media a VIC-20 doesn't take.
    def self.vic20(options, media)
      ram = options.ram
      unless media.nil?
        unsupported = Media::Vic20Media::UNSUPPORTED.include?(File.extname(media).downcase)
        raise Unsupported, "doesn't go in a VIC-20" if unsupported

        ram ||= vic20_ram(media)
      end
      Machine.build(:vic20, model: options.model, ram:)
    end

    def self.vic20_ram(media)
      ram = Media::Vic20Media.ram_for(media)
      puts "RAM expansion: #{ram}"
      ram
    end

    # Media the machine the options name doesn't take.
    class Unsupported < ArgumentError; end
  end
end
