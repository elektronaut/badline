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
    #   byte, the mechanism and what the ports read from it, and every
    #   byte of RAM it read or wrote as it found them (Bus#watch!)
    # - read nothing that changes from pass to pass: no counter, no shift
    #   register, and not VIA 1's port B, which reads the serial bus
    # - wrote nothing that reaches outside the drive: not VIA 1, whose port
    #   B drives the serial bus, and not the motor on
    # - ran while no counter could set a flag (VIA#quiet_cycles), with the
    #   motor off and no interrupt pulled.
    #
    # Such a pass runs the same way again from where it ended, for as
    # long as ATN holds still and no counter sets a flag, so the drive
    # sleeps: host_cycle! only counts the host cycles that go by. It wakes
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
    module Idle
      # Where the DOS 2.6 idle loop starts over.
      IDLE_LOOP = 0xebff

      # Whether the drive may sleep through its idle loop. On by default.
      attr_reader :idle_skip

      def idle_skip=(on)
        settle!
        @idle_skip = on
      end

      # Whether the drive is skipping its idle loop right now.
      def asleep? = @asleep

      # A host cycle asleep.
      def doze
        @slept += 1
        settle! if @slept == @wake_at || @serial_port.atn_moved?
      end

      # Brings the drive up to the present, cycle for cycle, and drops the
      # pass it was recording, since whoever called may change it. Every
      # reader of the drive's parts calls this.
      def settle!
        if @asleep
          wake!
          @serial_port.latch_host
        end
        stop_recording if @recording
      end

      private

      def init_idle
        @idle_skip = true
        @asleep = false
        @recording = false
        @owed = 0
        @budget = 0
        @slept = 0
        @wake_at = 0
        @pass_cycles = 0
        @pass_instructions = 0
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
        return if @mechanism.motor_on? || @via1.irq? || @via2.irq?

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
        @owed = 0
        @budget = quiet_cycles
      end

      # Asleep, host_cycle! counts host cycles, and leaves it to wake! to
      # turn them into drive cycles through the phase accumulator. This sets
      # the host cycle that brings the drive cycles owed up to the budget.
      def plan_wake
        @slept = 0
        needed = ((@budget - @owed) * @host_clock_hz) - @phase
        @wake_at = needed.positive? ? (needed + CLOCK_HZ - 1) / CLOCK_HZ : 1
      end

      # Runs the cycles owed: whole passes in bulk, up to the budget, and
      # the rest one by one.
      def wake!
        @asleep = false
        phase = @phase + (@slept * CLOCK_HZ)
        @phase = phase % @host_clock_hz
        owed = @owed + (phase / @host_clock_hz)
        @owed = 0
        @slept = 0
        span = [owed, @budget].min
        passes = span / @pass_cycles
        if passes.positive?
          cycles = passes * @pass_cycles
          @cpu.fast_forward(cycles, passes * @pass_instructions)
          @via1.fast_forward(cycles)
          @via2.fast_forward(cycles)
          @cycles += cycles
          owed -= cycles
        end
        owed.times { step }
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
        [*@cpu.idle_state, *@via1.idle_state, *@via2.idle_state, @bus.data,
         mechanism.motor_on?, mechanism.led_on?, mechanism.zone, mechanism.half_track, mechanism.disk,
         mechanism.read_a(0xff), mechanism.read_b(0xff)]
      end
    end
  end
end
