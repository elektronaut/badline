# frozen_string_literal: true

module Badline
  # = Machine
  #
  # The machines badline builds by family, as the command line's
  # subcommand names them. Only the C64, Computer, is built so far.
  #
  # A machine answers what the front end, Media, the runners and the
  # snapshots call on it:
  #
  # - Clocking: +run_cycles(n)+, +run_until(limit) { ... }+, +cycles+,
  #   +on_init+ and +init_threshold+, the cycle its handlers run at.
  # - Lifecycle: +reset!+ and +power_cycle!+.
  # - Video: +video+, the chip the screen reads (+display+, +width+,
  #   +dirty_lines+, +clear_dirty_lines!+ and +palette+), and +timing+, a
  #   Timing.
  # - Sound: +sound_source+, which answers +record(rate:)+,
  #   +drain_samples+ and +model+.
  # - Input: +keyboard+, +joystick1+, +joystick2+, +control_ports+ and
  #   +press_restore+.
  # - Media: +ram+, +load_prg+, +type_text+, +mount+, +unmount+,
  #   +mounted?+, +datasette+, +attach_cartridge+,
  #   +press_cartridge_button+, +release_cartridge_button+,
  #   +attach_drive1541+, +drive1541+, and +address_bus+ for its
  #   +cartridge+ and +detach_cartridge+.
  # - Snapshots and tests: +snapshot+, +restore+, +save_snapshot+,
  #   +install_debug_register+ and +capture_output+.
  module Machine
    # A new machine of `family` (:c64), the model of it `model` names
    # (Model::ALL), with its SID `sid_model` when not nil and an REU of
    # `reu` K when not nil.
    def self.build(family, model:, sid_model: nil, reu: nil)
      raise ArgumentError, "no machine family named #{family}" unless family == :c64

      profile = Model.named(model)
      Computer.new(vic_model: profile.vic_model, cia_model: profile.cia_model,
                   sid_model: sid_model || profile.sid_model, region: profile.region, reu:,
                   kernal: profile.kernal, datasette: profile.datasette)
    end
  end
end
