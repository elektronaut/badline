# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The 1541's disk mechanism behind the 1551's gate array. BYTE READY
      # sets BYTE LATCHED, which the CPU's port reads on P7 until the CPU
      # next reaches the TIA, and latches the byte read for the TIA's port
      # B. Nothing reaches an SO pin, which the 6510T doesn't have. In write
      # mode the write shift register loads what the TIA drives on port B.
      class Mechanism < Model1541::Mechanism
        # The TIA, whose port B the head writes from.
        attr_writer :tia

        # The GCR byte the last BYTE READY latched.
        attr_accessor :latched_byte

        def initialize
          @tia = nil
          @latched_byte = 0
          super
        end

        def byte_ready!
          @byte_latched = true
          @latched_byte = @shift & 0xff
        end

        def byte_ready_ended! = nil

        def save_fields(out)
          super.int("latched_byte", @latched_byte)
        end

        def load_fields(input, disk)
          super
          @latched_byte = input.byte("latched_byte", @latched_byte)
        end

        private

        def write_byte = @tia.port_b_output
      end
    end
  end
end
