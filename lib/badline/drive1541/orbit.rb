# frozen_string_literal: true

module Badline
  class Drive1541
    # Sleeping through the DOS's timer interrupts, exactly, once they come
    # round.
    #
    # VIA 2's timer 1 interrupts the idle loop for the job loop, which
    # finds no job, restarts the timer and returns into the pass it cut
    # into, 14,998 cycles and more apart. The interrupts land at a
    # different point in the pass each time, until, six of them on, the
    # whole drive is back where it was: an orbit of 90,044 cycles.
    #
    # Each place the drive falls asleep (see Idle) is an anchor, and the
    # drive keeps everything it holds at each one: RAM, the counters of
    # the timers that are armed or that it read or wrote since, and the
    # rest as Idle compares a pass. It keeps them only while it keeps to
    # itself, with Bus#guard! checking that it doesn't read the serial
    # bus, write VIA 1, turn the motor on or change the LED. ATN moving,
    # or a reader settling the drive, forgets them.
    #
    # Coming to an anchor it kept before closes an orbit, which runs the
    # same way again from here for as long as ATN holds still, so the
    # drive sleeps on without waking for its counters. Waking counts off
    # the whole orbits it owes in bulk, moving on only the counters it
    # never touched, and runs the rest as Idle does.
    module Orbit
      # How many anchors the drive keeps while it looks for an orbit.
      ANCHORS = 32

      private

      def init_orbits
        @anchors = {}
        @orbit_cycles = nil
        @orbit_instructions = 0
        @bus.guard!
      end

      # The drive falls asleep at an anchor. One it came to before closes
      # an orbit: everything from there to here runs the same way again.
      def anchor
        forget_orbits if @bus.tainted || @anchors.size >= ANCHORS
        key = anchor_state
        if (seen = @anchors[key])
          @orbit_cycles = @cycles - seen[0]
          @orbit_instructions = @cpu.instructions - seen[1]
        else
          @anchors[key] = [@cycles, @cpu.instructions]
        end
      end

      def forget_orbits
        @anchors.clear
        @orbit_cycles = nil
        @bus.guard!
      end

      # Runs whole orbits, which bring the drive back to the anchor it
      # sleeps at but for the counters it never touched. Returns the
      # cycles.
      def skip_orbits(orbits)
        cycles = orbits * @orbit_cycles
        touched = @bus.touched_timers
        @cpu.fast_forward(cycles, orbits * @orbit_instructions)
        @via1.skip_orbits(cycles, touched & 0x03)
        @via2.skip_orbits(cycles, touched >> 2)
        @cycles += cycles
        cycles
      end

      # Everything the drive holds at an anchor, but for the counters of
      # the unarmed timers it hasn't touched since it was last tainted.
      def anchor_state
        touched = @bus.touched_timers
        [*idle_state, *@via1.counter_state(touched & 0x03), *@via2.counter_state(touched >> 2),
         @bus.ram.snapshot]
      end
    end
  end
end
