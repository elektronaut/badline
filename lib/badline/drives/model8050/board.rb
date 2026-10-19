# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The board of a unit with two processors on the IEEE-488 bus, as the
      # 8050 family and the 4040 family share it: the interface processor
      # with its two 6532s on the bus, the floppy controller with its VIA
      # and 6530 facing the drives, and the common RAM between them. Each
      # unit's class includes it, with Idle and KeyedState, and builds its
      # own chips, so no call it makes on them is a union: the class sets
      # @ip_cpu, @fdc_cpu, @ip_bus, @fdc_bus, @common, @data_riot,
      # @control_riot, @via, @rriot, @mechanism, @ieee_bus and @ieee_port,
      # and runs one cycle of the board in its own step.
      #
      # The unit clocks against the host through a phase accumulator, as
      # Drives::Engine::Core does: each host cycle adds 1 MHz of phase, and
      # every whole host period in it runs a cycle of both processors. While
      # both processors idle, it sleeps instead (Idle), and the readers of
      # its parts catch it up first.
      module Board
        attr_reader :device, :ieee_bus

        def ip_cpu = settled(@ip_cpu)

        def fdc_cpu = settled(@fdc_cpu)

        def ip_bus = settled(@ip_bus)

        def fdc_bus = settled(@fdc_bus)

        def common = settled(@common)

        def data_riot = settled(@data_riot)

        def control_riot = settled(@control_riot)

        def via = settled(@via)

        def rriot = settled(@rriot)

        def mechanism = settled(@mechanism)

        def cycles
          settle!
          @cycles
        end

        attr_writer :host_clock_hz

        # Whether the unit is where VICE saves it: both processors between
        # instructions, the FDC at the start of its idle loop.
        def settled_for_vice?
          fdc = fdc_cpu
          ip_cpu.boundary? && fdc.boundary? && fdc.program_counter == @fdc_loop
        end

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

        # Which LEDs are lit: bit 0 drive 1's, bit 1 drive 0's, bit 2 the
        # error LED. They hold still while the unit sleeps, so reading them
        # leaves it asleep.
        def leds = @ieee_port.leds

        def led_on? = leds.anybits?(0x03)

        # Puts a Disk in +drive+, 0 or 1. Nil takes the disk out.
        def insert(disk, drive: 0)
          settle!
          @mechanism.insert(disk, drive)
        end

        # The Disk in +drive+, or nil.
        def disk(drive = 0) = @mechanism.disk(drive)

        # Stores what the heads wrote in the disks' images, as the motors
        # stopping do.
        def flush
          settle!
          @mechanism.flush
        end

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

        # The bus's IFC line resets both processors and every chip. RAM keeps
        # its contents.
        def reset!
          settle!
          @data_riot.reset!
          @control_riot.reset!
          @via.reset!
          @rriot.reset!
          @ip_cpu.reset!
          @fdc_cpu.reset!
        end

        def inspect
          "#<#{self.class.name} cycles=#{@cycles} ip=(#{@ip_cpu.inspect}) fdc=(#{@fdc_cpu.inspect})>"
        end

        private

        def settled(part)
          settle!
          part
        end

        def run_cycle
          step
          watch_loops if @idle_skip
        end
      end
    end
  end
end
