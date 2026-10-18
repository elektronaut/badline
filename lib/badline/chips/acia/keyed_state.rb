# frozen_string_literal: true

module Badline
  module Chips
    class ACIA
      # The registers, the status, the shift register and when the
      # transmitter's character ends, in a keyed snapshot module (BL-ACIA).
      # What the device on the line has still to send stays with the
      # host, and the receiver starts on it again once loaded (#restored!).
      # A snapshot from before the transmitter's timing was saved starts
      # its character clock on load.
      module KeyedState
        def save_fields(out)
          out.int("command", @command).int("control", @control).int("errors", @errors)
          out.bool("receiver_full", @receiver_full).bool("transmitter_empty", @transmitter_empty).bool("irq", @irq)
          out.int("receive_data", @receive_data).int("transmit_data", @transmit_data).int("shifting", @shifting)
          out.int("transmit_at", @transmit_at).int("transmit_remainder", @transmit_remainder)
        end

        def load_fields(input)
          @command = input.byte("command", @command)
          @control = input.byte("control", @control)
          @errors = input.masked("errors", 0, PARITY_ERROR | FRAMING_ERROR | OVERRUN)
          @receiver_full = input.bool("receiver_full", false)
          @transmitter_empty = input.bool("transmitter_empty", true)
          @irq = input.bool("irq", false)
          @receive_data = input.byte("receive_data", 0)
          @transmit_data = input.byte("transmit_data", 0)
          @shifting = input.int("shifting", IDLE)
          @transmit_remainder = input.int("transmit_remainder", 0)
          transmit_at = input.optional_int("transmit_at")
          @transmit_at = transmit_at || NEVER
          @clock_lost = transmit_at.nil?
        end

        def restored!
          @receive_at = NEVER
          @lines = modem_lines
          start_transmitting if @clock_lost && transmitter_on?
          @clock_lost = false
          start_receiving
          changed
        end
      end
    end
  end
end
