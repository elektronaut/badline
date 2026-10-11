# frozen_string_literal: true

module Badline
  class CIA
    # A snapshot of the chip: everything it holds but its wiring, the ports,
    # the PB4 and CNT levels, the timers, the interrupt register, the serial
    # port and the TOD clock.
    module SavedState
      def save_state(out)
        out.marker("CIA")
        out.int(@data_port_a).int(@data_port_b).int(@data_dir_a).int(@data_dir_b)
        out.boolean(@port_b4_high).boolean(@port_b4_driven_high).boolean(@cnt_high).boolean(@cnt_rise)
        out.int(@control_a.value).int(@control_b.value)
        @ta.save_state(out)
        @tb.save_state(out)
        @icr.save_state(out)
        @serial.save_state(out)
        @tod.save_state(out)
      end

      def load_state(input)
        input.marker("CIA")
        @data_port_a = input.int
        @data_port_b = input.int
        @data_dir_a = input.int
        @data_dir_b = input.int
        @port_b4_high = input.boolean?
        @port_b4_driven_high = input.boolean?
        @cnt_high = input.boolean?
        @cnt_rise = input.boolean?
        @control_a.value = input.int
        @control_b.value = input.int
        load_parts(input)
      end

      private

      def load_parts(input)
        @ta.load_state(input)
        @tb.load_state(input)
        @icr.load_state(input)
        @serial.load_state(input)
        @tod.load_state(input)
      end
    end
  end
end
