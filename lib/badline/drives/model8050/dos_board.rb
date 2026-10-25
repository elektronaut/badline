# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The half of the DOS board every unit with an interface processor
      # shares: the interface processor with its two 6532s on the IEEE-488
      # bus, the common RAM, and the second processor's VIA, whichever side
      # the second processor runs. Board adds the floppy controller's side
      # to it, and Model9060 the SASI host's. Each unit's class sets
      # @ip_cpu, @ip_bus, @common, @data_riot, @control_riot, @via,
      # @ieee_bus and @ieee_port, and has its own run_cycle and settle!.
      #
      # The unit clocks against the host through a phase accumulator, as
      # Drives::Engine::Core does: each host cycle adds 1 MHz of phase, and
      # every whole host period in it runs a cycle of both processors. While
      # both processors idle, it sleeps instead, and the readers of its
      # parts catch it up first. Asleep, a host cycle only counts towards
      # the one planned to wake the unit, which its own doze wakes, and a
      # line the controller moves wakes it at once (host_written!).
      module DOSBoard
        attr_reader :device, :ieee_bus

        def ip_cpu = settled(@ip_cpu)

        def ip_bus = settled(@ip_bus)

        def common = settled(@common)

        def data_riot = settled(@data_riot)

        def control_riot = settled(@control_riot)

        def via = settled(@via)

        def cycles
          settle!
          @cycles
        end

        attr_writer :host_clock_hz

        # Plugs the unit into an IEEE-488 bus, leaving the one it was on.
        def connect(ieee_bus)
          settle!
          @ieee_bus.detach(self)
          @ieee_bus = ieee_bus
          @ieee_port.bus = ieee_bus
          ieee_bus.attach(self)
        end

        # The lines the unit pulls on the bus while ATN is low or not
        # (IEEEPort).
        def ieee_low_lines(atn) = @ieee_port.ieee_low_lines(atn)

        # Which LEDs are lit, as the unit's port drives them. They hold
        # still while the unit sleeps, so reading them leaves it asleep.
        def leds = @ieee_port.leds

        def power_led_on? = true

        # Runs the drive cycles that fall in one host cycle, then takes the
        # controller's lines for the next. Asleep, the unit owes the cycles
        # instead, and wakes once the controller has moved a line, as it
        # does with a processor owing cycles (dozing?).
        def host_cycle!
          return if slept_through?

          phase = @phase + CLOCK_HZ
          while phase >= @host_clock_hz
            @asleep ? owe_cycle : run_cycle
            phase -= @host_clock_hz
          end
          @phase = phase
          settle! if dozing? && @ieee_port.lines_moved?
          @ieee_port.latch_host
          plan_sleep if @asleep
        end

        def cycle!
          settle!
          run_cycle
        end

        # The controller pushed its lines into the bus. A line it moved
        # wakes a unit that owes cycles, which saw the lines as they stood.
        def host_written!
          settle! if dozing? && @ieee_port.lines_moved?
        end

        private

        def settled(part)
          settle!
          part
        end

        # Asleep, a host cycle only counts towards the one planned to wake
        # the unit (plan_sleep). Returns whether it did.
        def slept_through?
          return false unless @planned

          @slept += 1
          doze if @slept == @wake_at
          true
        end

        # Plans the host cycle that brings the cycles owed up to the budget,
        # once the unit has fallen asleep and the host cycle it fell asleep
        # in is over.
        def plan_sleep
          return if @planned

          @planned = true
          @slept = 0
          needed = ((@budget - @owed) * @host_clock_hz) - @phase
          @wake_at = needed.positive? ? (needed + CLOCK_HZ - 1) / CLOCK_HZ : 1
        end

        # Turns the host cycles slept into cycles owed, through the phase
        # accumulator.
        def owe_slept
          return unless @planned

          @planned = false
          phase = @phase + (@slept * CLOCK_HZ)
          @owed += phase / @host_clock_hz
          @phase = phase % @host_clock_hz
          @slept = 0
        end
      end
    end
  end
end
