# frozen_string_literal: true

module Badline
  class Drive1541
    # Skipping the drive's cycles while the DOS idles, exactly.
    #
    # With nothing to do, the DOS goes round its idle loop from $EBFF,
    # 446 cycles a pass, until VIA 2's timer 1 interrupts it every 14,850
    # cycles for the job loop, or ATN interrupts it through VIA 1's CA1. A
    # pass writes RAM and VIA 2's port B, but puts back what it found, so
    # the drive comes round to $EBFF as it left it. Only the timers'
    # counters and the cycle counts move.
    #
    # Each time the CPU comes to $EBFF, the drive records the pass that
    # follows. At the next $EBFF it checks that the pass
    #
    # - left the CPU, both VIAs but for their counters, the bus's last
    #   byte, the SO pin, the mechanism (Mechanism#idle_state) and what
    #   the ports read from it, and every byte of RAM it read or wrote as
    #   it found them (Bus#watch!)
    # - read nothing that changes from pass to pass: no counter, no shift
    #   register, and not VIA 1's port B, which reads the serial bus
    # - wrote nothing that reaches outside the drive: not VIA 1, whose port
    #   B drives the serial bus, and not the motor on
    # - ran while no counter could set a flag (VIA#quiet_cycles), with the
    #   motor off, no interrupt pulled and no trap on the CPU.
    #
    # Such a pass runs the same way again from where it ended, for as
    # long as ATN holds still and no counter sets a flag, so the drive
    # sleeps: host_cycle! only counts the host cycles that go by (see
    # Sleep). It wakes
    # when ATN moves, when a counter is due to set a flag, or when something
    # outside reads or changes the drive (the readers in Drive1541 call
    # settle!). Waking counts off the whole passes it owes in bulk,
    # moving the counters on, and runs the rest cycle by cycle.
    #
    # The loop reads neither CLK nor DATA, so the drive sleeps through them
    # moving and takes the C64's lines as they stand once it wakes. Its
    # own lines hold still while it sleeps, so the C64 reads them without
    # waking it (serial_output).
    #
    # A pass starts at $EBFF, where the CPU always comes from the loop's
    # last instruction, a JMP, so what that leaves in the CPU's working
    # registers is the same each time round.
    #
    # The timer's interrupts come round too, and once they do, the drive
    # sleeps on through them (see Orbit).
    module Idle
      # Where the DOS 2.6 idle loop starts over.
      IDLE_LOOP = 0xebff

      # Whether the drive may sleep through its idle loop. On by default,
      # but for a drive whose CPU logs each instruction.
      attr_reader :idle_skip

      def idle_skip=(on)
        settle!
        @idle_skip = on
      end

      private

      def init_idle(debug)
        @idle_skip = !debug
        @recording = false
        @pass_cycles = 0
        @pass_instructions = 0
        init_sleep
        init_orbits
      end

      # The CPU is at $EBFF. At an instruction boundary, the drive sleeps if
      # the pass it recorded can repeat, and otherwise records the next.
      def idle_loop_reached
        return unless @cpu.boundary?

        if @recording
          stop_recording
          return fall_asleep if repeatable_pass? && room_for_pass?
        end
        start_recording
      end

      def start_recording
        return if @mechanism.motor_on? || @via1.irq? || @via2.irq? || @cpu.trapped?

        @recording = true
        @record_state = idle_state
        @record_cycles = @cycles
        @record_instructions = @cpu.instructions
        @record_quiet = quiet_cycles
        @bus.watch!
      end

      def stop_recording
        @recording = false
        @bus.unwatch!
      end

      # Whether the pass just recorded can repeat.
      def repeatable_pass?
        !@bus.volatile && @cycles - @record_cycles <= @record_quiet && idle_state == @record_state &&
          ram_as_found?
      end

      # Whether the counters leave room for a whole pass.
      def room_for_pass? = quiet_cycles >= @cycles - @record_cycles

      # Sleeps through the pass just recorded, over and over.
      def fall_asleep
        @pass_cycles = @cycles - @record_cycles
        @pass_instructions = @cpu.instructions - @record_instructions
        @asleep = true
        @host_still = false
        @owed = 0
        @budget = quiet_cycles
        anchor
      end

      def quiet_cycles
        [@via1.quiet_cycles, @via2.quiet_cycles].min
      end

      def ram_as_found?
        ram = @bus.ram
        @bus.touched.all? { |addr, value| ram.peek(addr) == value }
      end

      def idle_state
        mechanism = @mechanism
        [*@cpu.idle_state, *@via1.idle_state, *@via2.idle_state, @bus.data, @so_pending,
         *mechanism.idle_state, mechanism.read_a(0xff), mechanism.read_b(0xff)]
      end
    end
  end
end
