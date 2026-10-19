# frozen_string_literal: true

require "badline/chips/acia"
require "badline/chips/m6809"
require "badline/pet/superpet/dongle"
require "badline/pet/superpet/acia"
require "badline/pet/superpet/board"
require "badline/pet/superpet/m6809"
require "badline/pet/superpet/waterloo_traps"

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
    #
    # In 6809 mode device 8 answers through traps on the Waterloo ROM's
    # IEEE-488 routines (WaterlooTraps) as well as the KERNAL's, from the
    # same disk, or a true drive on the bus answers. type_text types
    # through the Waterloo ROM's key buffer, in ASCII, once its menu is up.
    class SuperPET < PET
      # The Waterloo ROM's key buffer: its read and write pointers, and the
      # ring of bytes they run round.
      KEYS_READ = 0x012c
      KEYS_WRITE = 0x012e
      KEYS_FIRST = 0x0130
      KEYS_END = 0x0158

      # The cycle by which the 6809 has put up the Waterloo menu, with a
      # margin.
      WATERLOO_BOOT = 600_000

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
        @waterloo_trap = nil
        @board.on_select { cpu_selected }
        @bus.fit_board(@board)
        @init_threshold = WATERLOO_BOOT if @m6809_running
      end

      # Whether an autostart finds BASIC: not while the 6809 runs.
      def boots_basic? = !@m6809_running

      # Device 8 through the traps, for the Waterloo ROM's routines too.
      def mount(storage)
        trap = super
        @waterloo_trap ||= WaterlooTraps.new(cpu: @m6809, bus: @bus, dos: @dos).install
        @waterloo_trap.device = trap_device
        trap
      end

      def unmount
        super
        @waterloo_trap&.uninstall
        @waterloo_trap = nil
      end

      def attach_ieee_drive(drive)
        super
        @waterloo_trap&.device = trap_device
      end

      def detach_ieee_drive
        super
        @waterloo_trap&.device = trap_device
      end

      # Types into the Waterloo ROM's key buffer, in ASCII, while the 6809
      # runs, and into the editor's otherwise.
      def type_text(text)
        return super unless @m6809_running

        type_on_init(text.bytes)
      end

      # Whether the 6809 has the bus, rather than the 6502.
      def m6809_running? = @m6809_running

      def superpet? = true

      # Moves the CPU switch to +position+, one of Board::CPU_SWITCH, and
      # resets the machine, so the CPU the switch picks starts from its
      # RESET.
      def switch_cpu(position)
        @board.cpu_switch = position
        reset!
      end

      # Moves the bank RAM switch to +position+, one of Board::RAM_SWITCH.
      def switch_bank_ram(position)
        @board.ram_switch = position
      end

      # Whether the picture shows the character ROM's APL set: its second
      # half, which the CRTC's MA13 picks, with VIA CA2 high.
      def apl_characters? = @crtc.registers[12].anybits?(0x20) && @via.ca2_output

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

      # The Waterloo ROM's ring takes keys until its write pointer would
      # meet its read pointer.
      def feed_keyboard
        return super unless @m6809_running

        read = word_at(KEYS_READ)
        write = word_at(KEYS_WRITE)
        until @pending_keys.empty?
          following = write + 1 == KEYS_END ? KEYS_FIRST : write + 1
          break if following == read

          @bus.poke(write, @pending_keys.shift)
          write = following
        end
        @bus.poke(KEYS_WRITE, write >> 8)
        @bus.poke(KEYS_WRITE + 1, write & 0xff)
        @pending_keys = nil if @pending_keys.empty?
      end

      def word_at(addr) = (@bus.peek(addr) << 8) | @bus.peek(addr + 1)

      # The CPU the board picks takes the bus over from its RESET.
      def cpu_selected
        @m6809_running = @board.m6809?
        @m6809_running ? @m6809.reset! : @cpu.reset!
      end
    end
  end
end
