# frozen_string_literal: true

module Badline
  # = Machine
  #
  # The machines badline builds by family, as the command line's
  # subcommand names them: the C64, Computer, and the VIC-20, Vic20.
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
  #   +attach_drive1541+, +drive1541+, and +address_bus+ for its
  #   +cartridge+ and +detach_cartridge+.
  # - Snapshots and tests: +snapshot+, +restore+, +save_snapshot+,
  #   +install_debug_register+ and +capture_output+.
  #
  # The VIC-20 answers the identity, clocking, lifecycle, video, sound and
  # input parts, with its one joystick as both +joystick1+ and +joystick2+
  # and nil for +control_ports+, and of the rest +ram+, +load_prg+,
  # +type_text+, +mount+, +unmount+, +mounted?+, +datasette+, +attach_cartridge+,
  # +attach_drive1541+, +drive1541+, +install_debug_register+ and
  # +capture_output+.
  module Machine
    # A new machine of `family`, :c64 or :vic20, the model of it `model`
    # names. A C64's model is one of Model::ALL, with its SID `sid_model`
    # when not nil and an REU of `reu` K when not nil. A VIC-20's is "pal",
    # with the RAM expansion `ram` names (Vic20::Bus::RAM_CONFIGURATIONS),
    # unexpanded when nil.
    def self.build(family, model:, sid_model: nil, reu: nil, ram: nil)
      return vic20(model, ram) if family == :vic20
      raise ArgumentError, "no machine family named #{family}" unless family == :c64

      profile = Model.named(model)
      Computer.new(vic_model: profile.vic_model, cia_model: profile.cia_model,
                   sid_model: sid_model || profile.sid_model, region: profile.region, reu:,
                   kernal: profile.kernal, datasette: profile.datasette, board: profile.board)
    end

    def self.vic20(model, ram)
      raise ArgumentError, "no VIC-20 model named #{model}" unless model == "pal"

      Vic20.new(ram: ram || :unexpanded)
    end
    private_class_method :vic20
  end
end
