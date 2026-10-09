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

      computer = nil
      problem = media_problem { computer = boot(options) }
      unless problem.empty?
        warn "#{options.program}: #{options.media_path}: #{problem}"
        return 1
      end
      timeline = Timeline.new(options)
      App.new(computer, options, timeline).run
      timeline.failed? ? 1 : 0
    end

    # Runs the block and returns the message of the error it raised over
    # media that won't go in or start, or an empty string. Other errors,
    # a bare ArgumentError among them, go through.
    def self.media_problem
      yield
      ""
    rescue Unsupported, Media::TrueDrive::Error, Media::DiskList::Error, Media::NotDisk, Datasette::Missing,
           SystemCallError, Storage::SIDFile::FormatError, Storage::T64::FormatError, Storage::TAP::FormatError,
           Storage::CRTFile::FormatError, Storage::G64Image::FormatError, Cartridge::UnsupportedTypeError,
           Snapshot::FormatError => e
      e.message
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
      computer = build(options, media)
      Media::TrueDrive.plug(computer) if options.true_drive?
      unless media.nil?
        puts Media.attach(computer, media, autostart: options.autostart?, subtune: options.subtune,
                                           disk: { read_only: !writable })
      end
      computer
    end

    def self.build(options, media)
      case options.family
      when :vic20 then vic20(options, media)
      when :c128 then c128(options, media)
      else c64(options, media)
      end
    end

    def self.c64(options, media)
      sid_model = options.sid_model || Media.sid_model(media, otherwise: nil)
      Machine.build(:c64, model: options.model, sid_model:, reu: options.reu)
    end

    # A C128 in C128 mode. With --c64, or media only C64 mode runs, a .sid
    # tune or a program that loads at the C64's BASIC start, C= is held
    # through the reset, so the C128 KERNAL starts C64 mode.
    def self.c128(options, media)
      sid_model = options.sid_model || Media.sid_model(media, otherwise: nil)
      machine = C128.new(model: options.model, sid_model:, mode: :c128)
      machine.hold_commodore_key if options.c64_mode? || c64_media?(media)
      machine
    end

    def self.c64_media?(media)
      return false if media.nil? || !File.file?(media)

      extension = File.extname(media).downcase
      return true if extension == ".sid"
      return false unless %w[.prg .p00].include?(extension)

      [Media::BASIC_START, Media::BASIC_START - 1].include?(Storage::P00.load_address(media))
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
