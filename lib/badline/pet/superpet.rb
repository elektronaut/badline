# frozen_string_literal: true

require "badline/chips/acia"
require "badline/chips/m6809"
require "badline/pet/superpet/dongle"
require "badline/pet/superpet/acia"
require "badline/pet/superpet/board"
require "badline/pet/superpet/m6809"

module Badline
  class PET
    # The SuperPET, the SP9000 or MMF 9000: an 8032 with the University of
    # Waterloo's board in its CPU socket, with 64K of bank RAM, a 6551
    # ACIA, the 6702 and a 6809E (Board). The board's ACIA pulls the PET's
    # IRQ line with the PIAs and the VIA. Its character ROM, 901640-01,
    # holds the 8032's in its first half and an ASCII and an APL set in
    # its second, which the CRTC's MA13 picks.
    #
    # Both CPUs sit on the same bus at the same 1 MHz, and one runs at a
    # time: SW2, the CPU switch, picks it, or with SW2 at PROG bit 0 of the
    # system latch. The one that takes the bus over starts from its RESET
    # (Fachat: "The 6502 does a RESET after being switched on"; on the
    # 324037 schematic one-shots gate the 6809's RES), and the other stops
    # where it is. The PET's IRQ line, the ACIA's with it, reaches both.
    class SuperPET < PET
      attr_reader :board, :acia, :dongle, :m6809

      # +cpu+ is SW2's position and +bank_ram+ SW1's, as Board names them.
      # The other arguments are the PET's for an 8032, its true drive's too.
      def initialize(refresh_hz: 50, debug: false, basic: nil, editor: nil, cpu: "6502", bank_ram: "rw",
                     true_drive_model: Drives::IEEEModels::DEFAULT)
        raise ArgumentError, "the CPU switch has no position #{cpu}" unless Board::CPU_SWITCH.include?(cpu)

        super(model: "superpet", refresh_hz:, debug:, basic:, editor:, true_drive_model:)
        @acia_irq = false
        @acia_due = Chips::ACIA::NEVER
        @acia = ACIA.new(self, 1_000_000)
        @dongle = Dongle.new(self)
        @board = Board.new(@bus, dongle: @dongle, acia: @acia, keyboard_ports: @keyboard_ports, cpu_switch: cpu,
                                 ram_switch: bank_ram, refresh_hz: @refresh_hz)
        @m6809 = M6809.new(@bus)
        @m6809_running = @board.m6809?
        @board.on_select { cpu_selected }
        @bus.fit_board(@board)
      end

      # Whether the 6809 has the bus, rather than the 6502.
      def m6809_running? = @m6809_running

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
        irq = @pia1.irq? || @pia2.irq? || @via.irq? || @acia_irq
        if @m6809_running
          @m6809.irq = irq
          @m6809.cycle!
        else
          @cpu.irq = irq
          @cpu.cycle!
        end
        clock_ieee_drives

        @cycles += 1
      end

      # The ACIA's IRQ line, and the cycle it next has something to do at.
      def acia_changed(irq, due)
        @acia_irq = irq
        @acia_due = due
      end

      # The RES line reaches the board's latches, the 6702, the ACIA and
      # both CPUs too.
      def reset!
        super
        @acia.reset!
        @m6809.reset!
        @board.reset!
      end

      def power_cycle!
        @board.power_on!
        super
      end

      private

      # The CPU the board picks takes the bus over from its RESET.
      def cpu_selected
        @m6809_running = @board.m6809?
        @m6809_running ? @m6809.reset! : @cpu.reset!
      end
    end
  end
end
