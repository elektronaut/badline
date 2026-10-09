# frozen_string_literal: true

module Badline
  module Drive
    # The drive asleep, as Idle and Orbit let it: host_cycle! counts the
    # host cycles that go by, and waking turns them into drive cycles
    # through the phase accumulator and runs them. Whole orbits and whole
    # passes go in bulk, and the rest cycle by cycle, which may find the
    # idle loop and put the drive back to sleep.
    #
    # The drive looks at ATN only when the machine may have moved it, as
    # it pushes its lines into the bus (IECBus#host_lines=).
    module Sleep
      # Whether the drive is skipping its idle loop right now.
      def asleep? = @asleep

      # Brings the drive up to the present, cycle for cycle, and drops the
      # pass it was recording and the orbits it found, since whoever called
      # may change it. Every reader of the drive's parts calls this.
      def settle!
        if @asleep
          wake!
          @serial_port.latch_host
          @asleep = false
          @orbit_cycles = nil
        end
        stop_recording if @recording
        forget_orbits
      end

      private

      def init_sleep
        @asleep = false
        @host_still = false
        @owed = 0
        @budget = 0
        @slept = 0
        @wake_at = 0
      end

      # A host cycle asleep that may wake the drive. The next ones need no
      # look at ATN until the machine pushes its lines again.
      def doze
        @host_still = true
        if @serial_port.atn_moved?
          settle!
        elsif @slept == @wake_at
          wake!
          @serial_port.latch_host
          plan_wake if @asleep
        end
      end

      # Asleep, host_cycle! counts host cycles, and leaves it to wake! to
      # turn them into drive cycles through the phase accumulator. This sets
      # the host cycle that brings the drive cycles owed up to the budget.
      # On an orbit the drive sleeps until something outside wakes it:
      # @slept counts from 1, so it never comes to 0.
      def plan_wake
        @slept = 0
        return @wake_at = 0 if @orbit_cycles

        needed = ((@budget - @owed) * @host_clock_hz) - @phase
        @wake_at = needed.positive? ? (needed + @clock_hz - 1) / @clock_hz : 1
      end

      # Runs the cycles owed.
      def wake!
        phase = @phase + (@slept * @clock_hz)
        @phase = phase % @host_clock_hz
        owed = @owed + (phase / @host_clock_hz)
        @owed = 0
        @slept = 0
        catch_up(owed)
      end

      # Runs +owed+ drive cycles: whole orbits and whole passes in bulk,
      # passes only up to the budget, and the rest cycle by cycle, which
      # may put the drive back to sleep.
      def catch_up(owed)
        while owed.positive?
          if @asleep
            if @orbit_cycles && owed >= @orbit_cycles
              owed -= skip_orbits(owed / @orbit_cycles)
              next
            end
            @orbit_cycles = nil
            passes = [owed, @budget].min / @pass_cycles
            if passes.positive?
              owed -= skip_passes(passes)
              next
            end
            @asleep = false
          end
          run_cycle
          owed -= 1
        end
      end

      # Runs whole passes, moving the counters on. Returns the cycles.
      def skip_passes(passes)
        cycles = passes * @pass_cycles
        @cpu.fast_forward(cycles, passes * @pass_instructions)
        @via1.fast_forward(cycles)
        @via2.fast_forward(cycles)
        fast_forward_chips(cycles)
        @cycles += cycles
        @budget -= cycles
        cycles
      end
    end
  end
end
