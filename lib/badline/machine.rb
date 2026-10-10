# frozen_string_literal: true

require "badline/machine/clocking"

module Badline
  # = Machine
  #
  # The machines badline builds by family, as the command line's
  # subcommand names them: the C64, Computer, the VIC-20, Vic20, and the
  # C128 in C64 mode, C128.
  #
  # A machine answers what the front end, Media, the runners and the
  # snapshots call on it:
  #
  # - Identity: +family+, the family it was built as.
  # - Clocking: +run_cycles(n)+, +run_until(limit) { ... }+, +cycles+,
  #   +on_init+ and +init_threshold+, the cycle its handlers run at.
  # - Lifecycle: +reset!+ and +power_cycle!+.
  # - Video: +video+, the chip the screen reads (+display+, +width+,
  #   +dirty_lines+, +clear_dirty_lines!+ and +palette+), and +timing+, a
  #   Timing.
  # - Sound: +sound_source+, which answers +record(rate:)+,
  #   +drain_samples+ and +model+.
  # - Input: +keyboard+, +joystick1+, +joystick2+, +control_ports+,
  #   +press_restore+ and +release_restore+.
  # - Media: +ram+, +load_prg+, +type_text+, +mount+, +unmount+,
  #   +mounted?+, +datasette+, +attach_cartridge+,
  #   +press_cartridge_button+, +release_cartridge_button+,
  #   +attach_drive1541+, +drive1541+, +true_drive+ and +plug_true_drive+
  #   for the drive Media::TrueDrive plugs in, +attach_drive1581+,
  #   +drive1581+ and +plug_drive1581+ for a 1581 (Drive1581::Slot), and
  #   +address_bus+ for its +cartridge+ and +detach_cartridge+.
  # - Snapshots and tests: +snapshot+, +restore+, +save_snapshot+,
  #   +install_debug_register+ and +capture_output+.
  #
  # The VIC-20 answers the identity, clocking, lifecycle, video, sound and
  # input parts, with its one joystick as both +joystick1+ and +joystick2+
  # and nil for +control_ports+, and of the rest +ram+, +load_prg+,
  # +type_text+, +mount+, +unmount+, +mounted?+, +datasette+, +attach_cartridge+,
  # +attach_drive1541+, +drive1541+, +true_drive+, +plug_true_drive+, the
  # 1581's, +install_debug_register+ and +capture_output+.
  #
  # The C128 answers all but the cartridge button, and besides +mode+,
  # :c64, as Machine.build builds it, or :c128, +vdc+, the VDC a front
  # end can show in place of +video+ once +vdc_shown=+ renders it,
  # +press_caps_lock+, +release_caps_lock+, +press_display_key+,
  # +release_display_key+, and +attach_drive1571+ and +drive1571+ for the
  # C128D's 1571, its true drive.
  #
  # Each machine includes Machine::Clocking for the clocking part.
  module Machine
    # Media the machine named doesn't take.
    class Unsupported < ArgumentError; end

    # A new machine of `family`, :c64, :vic20 or :c128, the model of it
    # `model` names. A C64's model is one of Model::ALL, with its SID
    # `sid_model` when not nil and an REU of `reu` K when not nil. A
    # VIC-20's is "pal", with the RAM expansion `ram` names
    # (Vic20::Bus::RAM_CONFIGURATIONS), unexpanded when nil. A C128's is
    # one of C128::Model::ALL, with its SID `sid_model` when not nil, built
    # for C64 mode.
    def self.build(family, model:, sid_model: nil, reu: nil, ram: nil)
      return vic20(model, ram) if family == :vic20
      return c128(model, sid_model, :c64) if family == :c128
      raise ArgumentError, "no machine family named #{family}" unless family == :c64

      profile = Model.named(model)
      Computer.new(vic_model: profile.vic_model, cia_model: profile.cia_model,
                   sid_model: sid_model || profile.sid_model, region: profile.region, reu:,
                   kernal: profile.kernal, datasette: profile.datasette, board: profile.board)
    end

    # The machine the command line's `options` name, to start `media`, a
    # path or nil. A C64 or a C128 without a SID named takes the one a .sid
    # tune names. The C128 is built for C128 mode, with C= held through the
    # reset, so its KERNAL starts C64 mode, for --c64 (+c64_mode?+) or media
    # only C64 mode runs: a .sid tune or a program that loads at the C64's
    # BASIC start. A VIC-20 without RAM named gets the expansion the media
    # needs (Media::Vic20Media.ram_for) and yields a line saying so. Raises
    # Unsupported for media a VIC-20 doesn't take.
    def self.for_options(options, media, &)
      family = options.family
      return vic20_for(media, options.model, options.ram, &) if family == :vic20

      sid_model = options.sid_model || Media.sid_model(media, otherwise: nil)
      return build(:c64, model: options.model, sid_model:, reu: options.reu) unless family == :c128

      machine = c128(options.model, sid_model, :c128)
      machine.hold_commodore_key if options.c64_mode? || c64_media?(media)
      machine
    end

    def self.vic20(model, ram)
      raise ArgumentError, "no VIC-20 model named #{model}" unless model == "pal"

      Vic20.new(ram: ram || :unexpanded)
    end
    private_class_method :vic20

    def self.c128(model, sid_model, mode) = C128.new(model:, sid_model:, mode:)
    private_class_method :c128

    def self.vic20_for(media, model, ram)
      unless media.nil?
        unsupported = Media::Vic20Media::UNSUPPORTED.include?(File.extname(media).downcase)
        raise Unsupported, "doesn't go in a VIC-20" if unsupported

        unless ram
          ram = Media::Vic20Media.ram_for(media)
          yield "RAM expansion: #{ram}"
        end
      end
      build(:vic20, model:, ram:)
    end
    private_class_method :vic20_for

    def self.c64_media?(media)
      return false if media.nil? || !File.file?(media)

      extension = File.extname(media).downcase
      return true if extension == ".sid"
      return false unless %w[.prg .p00].include?(extension)

      [Media::BASIC_START, Media::BASIC_START - 1].include?(Storage::P00.load_address(media))
    end
    private_class_method :c64_media?
  end
end
