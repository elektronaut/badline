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
      error = Timeline.error(options.timeline, options.p500? ? :p500 : options.family)
      unless error.empty?
        warn "#{options.program}: #{error}"
        return 1
      end

      computer = nil
      problem = if cartridge?(options)
                  cartridge_problem { computer = boot(options) }
                else
                  media_problem { computer = boot(options) }
                end
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
    rescue Machine::Unsupported, Media::TrueDrive::Error, Media::DiskList::Error, Media::NotDisk, Drives::Datasette::Missing,
           SystemCallError, SIDTune::File::FormatError, Storage::T64::FormatError, Storage::TAP::FormatError,
           Storage::CRTFile::FormatError, Storage::G64Image::FormatError, C64::Cartridge::UnsupportedTypeError,
           Snapshot::FormatError => e
      e.message
    end

    # Runs the block that puts a cartridge in, as media_problem does, and
    # also returns the message of the ArgumentError a machine raises over a
    # cartridge with a chip in a bank or slot it doesn't map.
    def self.cartridge_problem(&)
      media_problem(&)
    rescue ArgumentError => e
      e.message
    end

    # Whether the media the options start is a .crt.
    def self.cartridge?(options)
      media = options.media_path
      !media.nil? && Media::Extensions.kind(media) == :cartridge
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

    # A new machine built from the options (Machine.for_options), with
    # `media`, if not nil, attached and started as the command line does,
    # its disk writable if `writable`, after the Plus/4's cartridges the
    # options put in its slots. The VIC-20 and the Plus/4 raise
    # Machine::Unsupported for a .sid tune.
    def self.start(options, media, writable)
      computer = build(options, media)
      Media::TrueDrive.plug(computer) if options.true_drive?
      options.cartridges.each { |slot, path| puts Media.attach(computer, path, cartridge: { slot: }) }
      unless media.nil?
        puts Media.attach(computer, media, autostart: options.autostart?, subtune: options.subtune,
                                           disk: { read_only: !writable })
      end
      computer
    end

    # The machine the options name, built for `media`, which says the RAM
    # expansion a VIC-20 gets for it.
    def self.build(options, media)
      Machine.for_options(options, media) { |line| puts line }
    end
  end
end
