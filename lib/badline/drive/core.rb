# frozen_string_literal: true

module Badline
  module Drive
    # What every Commodore disk drive here shares: a 6502 running the DOS
    # ROM with two VIAs on its bus, VIA 1 facing the serial bus and VIA 2
    # the disk mechanism, on a clock of its own.
    #
    # The drive runs on its own crystal, so it clocks against the host's
    # clock through a fractional accumulator: each host cycle adds the
    # drive's clock rate worth of phase, and every whole host period in it
    # runs a drive cycle. Against the PAL C64's 985,248 Hz a drive at
    # 1 MHz runs one drive cycle per host cycle and a second one about
    # every 67. The host sets its clock on attaching the drive, and until
    # then a 1 MHz drive runs one cycle per host cycle.
    #
    # VIA 2's port B runs the Mechanism, which reads a Disk put in with
    # insert.
    #
    # While the DOS idles, host_cycle! skips the drive's cycles and catches
    # up on them later, exactly (see Idle). The readers of the drive's parts
    # catch up first, so they find the drive as running every cycle would
    # have left it. Once the DOS's timer interrupts come round, the drive
    # sleeps through them too (see Orbit).
    #
    # A model includes Core and builds its parts, sets @clock_hz and
    # @idle_loop, and runs one drive cycle in step.
    module Core
      include Sleep
      include Idle
      include Orbit

      attr_reader :device, :serial_bus

      def cpu
        settle!
        @cpu
      end

      def bus
        settle!
        @bus
      end

      def via1
        settle!
        @via1
      end

      def via2
        settle!
        @via2
      end

      def mechanism
        settle!
        @mechanism
      end

      def cycles
        settle!
        @cycles
      end

      def ram = bus.ram

      def host_clock_hz=(clock_hz)
        settle!
        @host_clock_hz = clock_hz
      end

      # Plugs the drive into a serial bus, leaving the one it was on. A drive
      # starts out on a bus of its own, with nothing else on it.
      def connect(serial_bus)
        settle!
        @serial_bus&.detach(self)
        @serial_bus = serial_bus
        @serial_port.bus = serial_bus
        serial_bus.attach(self)
        @via1.ca1 = @serial_port.atn_low?
      end

      # Puts a Disk in the drive (Disk.from_d64 makes one from an image).
      # Nil takes the disk out.
      def insert(disk)
        settle!
        @mechanism.insert(disk)
      end

      def disk = mechanism.disk

      # Whether the LED is lit. Reading it leaves the drive asleep: the LED
      # is the same at the end of every pass the drive sleeps through.
      def led_on? = @mechanism.led_on?

      # VIA 1's port B as it drives the serial bus. It holds still while the
      # drive sleeps, so reading it leaves the drive asleep.
      def serial_output = @via1.port_b_output

      # Stores what the head wrote since the motor last stopped in the
      # disk's image, as the motor stopping does.
      def flush
        settle!
        @mechanism.flush
      end

      # The serial bus's RESET line reaches the CPU and both VIAs. RAM keeps
      # its contents.
      def reset!
        settle!
        @via1.reset!
        @via2.reset!
        @cpu.reset!
      end

      # Runs the drive cycles that fall in one host cycle: none, one or two.
      # The host has run this cycle already, and the drive sees what it did
      # from the next one on (see SerialPort). Asleep, the drive owes the
      # cycles instead, until ATN moves or its counters are due (see Idle).
      # It looks at ATN only after the machine pushed its lines into the bus
      # (see host_written!).
      def host_cycle!
        if @asleep
          return if (@slept += 1) != @wake_at && @host_still

          return doze
        end

        phase = @phase + @clock_hz
        while phase >= @host_clock_hz
          @asleep ? @owed += 1 : run_cycle
          phase -= @host_clock_hz
        end
        @phase = phase
        settle! if @serial_port.atn_moved?
        @serial_port.latch_host
        plan_wake if @asleep
      end

      # The machine pushed its lines into the bus, so ATN may have moved.
      def host_written!
        @host_still = false
      end

      # The host moved its fast serial pins, which a 1541 has none to hear.
      def fast_lines_moved = nil

      # Runs one drive cycle, catching up first on any the drive owes (see
      # step).
      def cycle!
        settle!
        step
      end

      def inspect
        "#<#{self.class.name} cycles=#{cycles} cpu=(#{cpu.inspect})>"
      end

      private

      # Runs the model's chips beyond the VIAs +cycles+ quiet cycles at once
      # (see quiet_cycles). The 1541 has none.
      def fast_forward_chips(_cycles) = nil

      # A drive cycle from host_cycle!, which may find the idle loop.
      def run_cycle
        step
        idle_loop_reached if @cpu.program_counter == @idle_loop && @idle_skip
      end
    end
  end
end
