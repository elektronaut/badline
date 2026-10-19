# frozen_string_literal: true

require "badline/machine/clocking"
require "badline/machine/keyboard_buffer"
require "badline/machine/settling"

module Badline
  # = Machine
  #
  # The machines badline builds by family, as the command line's
  # subcommand names them: the C64, Badline::C64, the VIC-20, Vic20, the
  # C128 in C64 mode, C128, the 264 series, Plus4, and the PET and CBM,
  # PET.
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
  #   +drive1581+ and +plug_drive1581+ for a 1581 (Drives::Model1581::Slot), and
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
  # The Plus/4 answers the identity, clocking, lifecycle, video, sound and
  # input parts, with nil for +control_ports+ and no RESTORE, and of the
  # rest +ram+, +load_prg+, +type_text+, +mount+, +unmount+, +mounted?+,
  # +datasette+, +attach_cartridge+, +attach_drive1541+, +drive1541+,
  # +true_drive+, +plug_true_drive+, the 1581's, +install_debug_register+
  # and +capture_output+, and besides +model_label+, +cartridge_slots+ and
  # +detach_cartridges+ for its two cartridges.
  #
  # The PET answers the identity, clocking, lifecycle, video, sound and
  # keyboard parts, with no joysticks, RESTORE or control ports, and of
  # the rest +ram+, +load_prg+, +type_text+, +mount+, +unmount+,
  # +mounted?+, +datasette+, +true_drive+, nil, +install_debug_register+
  # and +capture_output+, and besides +model_label+ and +ram_kb+.
  #
  # Each machine includes Machine::Clocking for the clocking part.
  module Machine
    # Media the machine named doesn't take.
    class Unsupported < ArgumentError; end

    # A new machine of `family`, :c64, :vic20, :c128, :plus4, :pet or :cbm2, the
    # model of it `model` names. A C64's model is one of Model::ALL, with
    # its SID `sid_model` when not nil and an REU of `reu` K when not nil.
    # A VIC-20's is "pal" or "ntsc", with the RAM expansion `ram` names
    # (Vic20::Bus::RAM_CONFIGURATIONS), unexpanded when nil. A C128's is
    # one of C128::Model::ALL, with its SID `sid_model` when not nil, built
    # for C64 mode. A Plus/4's is one of Plus4::Model::ALL or c116, with
    # the model's own RAM. A PET's is one of PET::Model::ALL, with its own
    # RAM and ROMs, its CRTC's editor the 50 Hz one. A CBM-II's is one of
    # CBM2::Model::ALL, with VICE's KERNAL, 901244-04a, at 50 Hz, or a 510,
    # one of CBM2::P500::Model::ALL, with its region's mains.
    def self.build(family, model:, sid_model: nil, reu: nil, ram: nil)
      return vic20(model, ram) if family == :vic20
      return c128(model, sid_model, :c64) if family == :c128
      return Plus4.new(model:) if family == :plus4
      return PET.new(model:) if family == :pet
      return CBM2::P500.new(model:) if family == :cbm2 && model.start_with?("510")
      return CBM2.new(model:) if family == :cbm2
      raise ArgumentError, "no machine family named #{family}" unless family == :c64

      profile = Model.named(model)
      C64.new(vic_model: profile.vic_model, cia_model: profile.cia_model,
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
    # Unsupported for media a VIC-20, a Plus/4, a PET or a CBM-II doesn't
    # take.
    def self.for_options(options, media, &)
      family = options.family
      return vic20_for(media, options.model, options.ram, &) if family == :vic20
      return plus4_for(media, options) if family == :plus4
      return pet_for(media, options) if family == :pet
      return cbm2_for(media, options) if family == :cbm2

      sid_model = options.sid_model || Media.sid_model(media, otherwise: nil)
      return build(:c64, model: options.model, sid_model:, reu: options.reu) unless family == :c128

      machine = c128(options.model, sid_model, :c128)
      machine.hold_commodore_key if options.c64_mode? || c64_media?(media)
      machine
    end

    def self.vic20(model, ram) = Vic20.new(ram: ram || :unexpanded, model:)
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

    # A Plus/4 with the RAM --ram names (Plus4::Model::RAM_SIZES), or with
    # the model's own without it, the true drive --drive-type names, the
    # SID card --sid-card names, where --sid-card-address puts it, and the
    # RAM expansion --ram-expansion names.
    def self.plus4_for(media, options)
      unsupported = !media.nil? && Media::Vic20Media::UNSUPPORTED.include?(File.extname(media).downcase)
      raise Unsupported, "doesn't go in a Plus/4" if unsupported

      Plus4.new(model: options.model, ram: options.ram_kb, true_drive_model: options.drive_type,
                sid_card: options.sid_card, sid_card_address: options.sid_card_address || 0xfd40,
                ram_expansion: options.ram_expansion)
    end
    private_class_method :plus4_for

    # A PET with the RAM --ram names (PET::Model::RAM_SIZES), or with the
    # model's own without it, the editor at the frame rate --60hz or
    # --editor asks for, the ROMs --basic, --editor and --characters fit it
    # with, and the 8296 board's jumpers --jumpers names.
    def self.pet_for(media, options)
      unsupported = !media.nil? && Media::PETMedia::UNSUPPORTED.include?(File.extname(media).downcase)
      raise Unsupported, "doesn't go in a PET" if unsupported

      PET.new(model: options.model, ram_kb: options.ram_kb, refresh_hz: options.refresh_hz, basic: options.basic,
              editor: options.editor, characters: options.characters, jumpers: options.jumpers)
    end
    private_class_method :pet_for

    # A CBM-II with the KERNAL --kernal names, on the mains --60hz asks
    # for: a B series' 50 Hz without it, and a P500's its region's.
    def self.cbm2_for(media, options)
      unsupported = !media.nil? && Media::CBM2Media::UNSUPPORTED.include?(File.extname(media).downcase)
      raise Unsupported, "doesn't go in a CBM-II" if unsupported
      return CBM2::P500.new(model: options.model, mains_hz: options.mains_hz) if options.p500?

      CBM2.new(model: options.model, kernal: options.kernal, mains_hz: options.mains_hz || 50)
    end
    private_class_method :cbm2_for

    def self.c64_media?(media)
      return false if media.nil? || !File.file?(media)

      extension = File.extname(media).downcase
      return true if extension == ".sid"
      return false unless Media::Extensions::PROGRAMS.include?(extension)

      [Media::BASIC_START, Media::BASIC_START - 1].include?(Storage::P00.load_address(media))
    end
    private_class_method :c64_media?
  end
end
