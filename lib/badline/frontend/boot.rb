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
             Cartridge::UnsupportedTypeError, Snapshot::FormatError => e
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

      computer = Computer.new(sid_model: options.sid_model || Media.sid_model(media), reu: options.reu,
                              region: options.ntsc? ? Region::NTSC : Region::PAL)
      Media::TrueDrive.plug(computer) if options.true_drive?
      unless media.nil?
        puts Media.attach(computer, media, autostart: options.autostart?, subtune: options.subtune,
                                           disk: { read_only: options.read_only? })
      end
      computer
    end
  end
end
