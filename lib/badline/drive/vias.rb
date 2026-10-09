# frozen_string_literal: true

module Badline
  module Drive
    # The two VIAs the 1541 and the 1571 share: VIA 1 facing the serial
    # bus, its CA1 on ATN, and VIA 2 running the GCR Mechanism. A model
    # includes it beside Core, and it answers Core's, Idle's and Orbit's
    # questions about the chips: what they hold, how long their counters
    # leave them quiet, and how to run them a stretch at once. A model with
    # more chips on its bus runs them in fast_forward_more.
    module VIAs
      def via1
        settle!
        @via1
      end

      def via2
        settle!
        @via2
      end

      # Puts in a Disk from the .d64, .g64, .d71 or .g71 image at +path+
      # (Drive1541::Disk.open), write-protected with `read_only`.
      def insert_image(path, read_only: false)
        insert(Drive1541::Disk.open(path, read_only:))
      end

      # VIA 1's port B as it drives the serial bus. It holds still while the
      # drive sleeps, so reading it leaves the drive asleep.
      def serial_output = @via1.port_b_output

      # The serial bus's RESET line reaches the CPU and both VIAs. RAM keeps
      # its contents.
      def reset!
        settle!
        @via1.reset!
        @via2.reset!
        @cpu.reset!
      end

      private

      # ATN reaches VIA 1's CA1 as the serial port latched it.
      def hear_atn
        @via1.ca1 = @serial_port.atn_low?
      end

      # Whether the drive is doing anything a pass of the idle loop can't
      # repeat: the motor on, or a VIA pulling IRQ.
      def busy_for_pass? = @mechanism.motor_on? || @via1.irq? || @via2.irq?

      def quiet_cycles
        [@via1.quiet_cycles, @via2.quiet_cycles].min
      end

      def idle_state
        mechanism = @mechanism
        [*@cpu.idle_state, *@via1.idle_state, *@via2.idle_state, @bus.data, mechanism.so_pending,
         *mechanism.idle_state, mechanism.read_a(0xff), mechanism.read_b(0xff)]
      end

      # The counters an orbit has to bring back (VIA#counter_state).
      def counter_state(touched)
        [*@via1.counter_state(touched & 0x03), *@via2.counter_state(touched >> 2)]
      end

      def fast_forward_chips(cycles)
        @via1.fast_forward(cycles)
        @via2.fast_forward(cycles)
        fast_forward_more(cycles)
      end

      def skip_chip_orbits(cycles, touched)
        @via1.skip_orbits(cycles, touched & 0x03)
        @via2.skip_orbits(cycles, touched >> 2)
        fast_forward_more(cycles)
      end

      # Runs the model's chips beyond the VIAs +cycles+ quiet cycles at once
      # (see quiet_cycles). The 1541 has none.
      def fast_forward_more(_cycles) = nil
    end
  end
end
