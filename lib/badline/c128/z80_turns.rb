# frozen_string_literal: true

module Badline
  class C128
    # The Z80's turns on the bus. MCR bit 0 hands the bus between the 8502
    # and the Z80, and while the Z80 has it each cycle clocks the chips,
    # then gives the Z80 2 T-states unless BA holds it. The Z80 runs whole
    # instructions while it is behind, so an IN or OUT first brings the
    # chips up to the cycle it falls in (#z80_catch_up), and the cycles
    # that follow clock nothing until the machine catches up with them.
    module Z80Turns
      # The T-states from the start of an I/O machine cycle to the one its
      # data moves in. 1 and 2 pass c128modez80-23, whose IN reads open
      # bus, and 0, 3 and 4 fail it.
      IO_DELAY = 2

      attr_reader :z80

      # Brings the chips up to the cycle an IN or OUT of the Z80 falls in.
      def z80_catch_up
        while @z80.cycles + IO_DELAY >= @z80_due
          clock_chips
          @chips_ahead += 1
          @z80_due += 2
        end
      end

      private

      def build_z80
        z80_bus = Z80Bus.new(@bus)
        @z80 = Z80.new(z80_bus)
        z80_bus.machine = self
        @z80_running = @bus.z80?
        @z80_turn = @z80_running
        @z80_due = 0
        @chips_ahead = 0
        @cpu_reset_pending = @z80_running
        @bus.on_processor_change { processor_changed }
      end

      # A cycle while the Z80 has the bus, or after it handed the bus to the
      # 8502 while the chips were ahead.
      def z80_cycle!
        if @chips_ahead.positive?
          @chips_ahead -= 1
          @z80_turn = @z80_running || @chips_ahead.positive?
          return
        end

        clock_chips
        @z80_due += 2 unless @vic.ba_low?
        z80 = @z80
        z80.step! while @z80_running && z80.cycles < @z80_due
      end

      # The chips' share of a cycle while the Z80 has the bus, with the
      # interrupt lines going to the Z80.
      def clock_chips
        handle_init if @cycles == @init_threshold
        feed_keyboard if @pending_keys

        clock_bits = @clock_bits
        @clock_bits = @vic.clock_bits
        @vic.test_step! if clock_bits >= 0x02

        @vic.cycle!
        @cia1.cycle!
        @cia2.cycle!
        @sid.cycle!
        @datasette.cycle!
        @vdc.cycle!

        @z80.int = @cia1.interrupted? || @vic.interrupted?
        nmi = @cia2.interrupted? || @cartridge_nmi || @restore_pulse
        @restore_pulse = false
        @nmi_asserted = nmi
        @z80.nmi = nmi
        clock_serial_bus

        @cycles += 1
      end

      # MCR bit 0 handed the bus to the other CPU. The 8502 runs its reset
      # vector the first time it gets the bus after a reset.
      def processor_changed
        @z80_running = @bus.z80?
        @z80_turn = @z80_running || @chips_ahead.positive?
        @z80_due = @z80.cycles
        return if @z80_running || !@cpu_reset_pending

        @cpu_reset_pending = false
        @cpu.reset!
      end

      # The RES line reaches the Z80, and the 8502 waits for the bus to run
      # its reset vector, unless the machine resets into C64 mode.
      def reset_z80
        @chips_ahead = 0
        @z80_turn = @z80_running
        @z80.reset!
        @c64_built ? @cpu.reset! : @cpu_reset_pending = true
      end
    end
  end
end
