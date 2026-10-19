# frozen_string_literal: true

require "badline/chips/acia"
require "badline/pet/superpet/dongle"
require "badline/pet/superpet/acia"
require "badline/pet/superpet/board"

module Badline
  class PET
    # The SuperPET, the SP9000 or MMF 9000: an 8032 with the University of
    # Waterloo's board in its CPU socket, with 64K of bank RAM, a 6551
    # ACIA, the 6702 and the 6809 (Board). The board's ACIA pulls the
    # PET's IRQ line with the PIAs and the VIA. Its character ROM,
    # 901640-01, holds the 8032's in its first half, which the CRTC's MA13
    # picks.
    #
    # Only the 6502 runs so far, with SW2, the CPU switch, at 6502.
    class SuperPET < PET
      attr_reader :board, :acia, :dongle

      # +cpu+ is SW2's position and +bank_ram+ SW1's, as Board names them.
      # The other arguments are the PET's for an 8032, its true drive's too.
      def initialize(refresh_hz: 50, debug: false, basic: nil, editor: nil, cpu: "6502", bank_ram: "rw",
                     true_drive_model: Drives::IEEEModels::DEFAULT)
        raise ArgumentError, "the CPU switch has no position #{cpu}" unless Board::CPU_SWITCH.include?(cpu)
        raise ArgumentError, "the SuperPET's 6809 isn't emulated yet" unless cpu == "6502"

        super(model: "superpet", refresh_hz:, debug:, basic:, editor:, true_drive_model:)
        @acia_irq = false
        @acia_due = Chips::ACIA::NEVER
        @acia = ACIA.new(self, 1_000_000)
        @dongle = Dongle.new(self)
        @board = Board.new(@bus, dongle: @dongle, acia: @acia, keyboard_ports: @keyboard_ports, cpu_switch: cpu,
                                 ram_switch: bank_ram)
        @bus.fit_board(@board)
      end

      def superpet? = true

      # The 32K below $8000 and the 64K board.
      def model_label = "SUPERPET, 96K RAM, #{@refresh_hz} HZ"

      # The PET's cycle, with the ACIA run when it falls due and its IRQ
      # on the CPU's.
      def cycle!
        handle_init if @cycles == @init_threshold
        feed_keyboard if @pending_keys

        @crtc.cycle!
        drive_retrace(!@crtc.vsync?)
        @pia1.cycle!
        @pia2.cycle!
        @via.cycle!
        @sound.cycle! if @sound.recording?
        @cassettes.cycle! if @tapes_running
        @acia.run!(@cycles) if @cycles >= @acia_due
        @cpu.irq = @pia1.irq? || @pia2.irq? || @via.irq? || @acia_irq
        @cpu.cycle!
        clock_ieee_drives

        @cycles += 1
      end

      # The ACIA's IRQ line, and the cycle it next has something to do at.
      def acia_changed(irq, due)
        @acia_irq = irq
        @acia_due = due
      end

      # The RES line reaches the board's latches, the 6702 and the ACIA too.
      def reset!
        super
        @acia.reset!
        @board.reset!
      end

      def power_cycle!
        @board.power_on!
        super
      end
    end
  end
end
