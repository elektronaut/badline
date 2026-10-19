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
      # parts catch it up first.
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

        # The controller pushed its lines into the bus.
        def host_written! = nil

        # Which LEDs are lit, as the unit's port drives them. They hold
        # still while the unit sleeps, so reading them leaves it asleep.
        def leds = @ieee_port.leds

        def power_led_on? = true

        # Runs the drive cycles that fall in one host cycle, then takes the
        # controller's lines for the next. Asleep, the unit owes the cycles
        # instead, and wakes once the controller has moved a line.
        def host_cycle!
          phase = @phase + CLOCK_HZ
          while phase >= @host_clock_hz
            @asleep ? owe_cycle : run_cycle
            phase -= @host_clock_hz
          end
          @phase = phase
          settle! if @asleep && @ieee_port.lines_moved?
          @ieee_port.latch_host
        end

        def cycle!
          settle!
          run_cycle
        end

        private

        def settled(part)
          settle!
          part
        end
      end
    end
  end
end
