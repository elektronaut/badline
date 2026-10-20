# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The board of a unit with two processors on the IEEE-488 bus, as the
      # 8050 family and the 4040 family share it: the DOS board's interface
      # processor side (DOSBoard), and the floppy controller with its VIA
      # and 6530 facing the drives. Each unit's class includes it, with
      # Idle and KeyedState, and builds its own chips, so no call it makes
      # on them is a union: the class sets DOSBoard's fields and @fdc_cpu,
      # @fdc_bus, @rriot and @mechanism, and runs one cycle of the board in
      # its own step. While both processors idle, it sleeps (Idle).
      module Board
        include DOSBoard

        def fdc_cpu = settled(@fdc_cpu)

        def fdc_bus = settled(@fdc_bus)

        def rriot = settled(@rriot)

        def mechanism = settled(@mechanism)

        # Whether the unit is where VICE saves it: both processors between
        # instructions, the FDC at the start of its idle loop.
        def settled_for_vice?
          fdc = fdc_cpu
          ip_cpu.boundary? && fdc.boundary? && fdc.program_counter == @fdc_loop
        end

        # Whether a drive's LED is lit: of the LEDs, bit 0 is drive 1's,
        # bit 1 drive 0's, and bit 2 the error LED.
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

        def run_cycle
          return fdc_alone_cycle if @fdc_alone

          step
          watch_loops if @idle_skip
        end
      end
    end
  end
end
