# frozen_string_literal: true

module Badline
  module Drives
    class Model9060
      # The SASI host's VIA, at $0080, a class of its own so it keeps one
      # type of peripheral.
      class SASIVIA < Chips::VIA
      end

      # The SASI host's 6502, on the SASIBus.
      class SASICPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end

      # The VIA's lines to the controller (SASITarget), on the board's
      # transceivers:
      #
      #   PA0-7  the data bus             PB0  SEL out
      #   CA1    REQ, rising as it rises  PB1  RST out
      #   CA2    ACK, pulsed on each      PB2  C/D in
      #          read or write of ORA     PB3  BSY in
      #   CB2    the transceivers'        PB4  jumper J14: high for four
      #          direction                     heads (D9060), low for six
      #                                   PB6  I/O in
      #                                   PB7  MSG in
      #
      # The ports read and drive each line high while it is asserted, SEL
      # and RST only while PB0 and PB1 are outputs.
      # SEL raised selects the controller with the data bus as the host
      # drives it, and RST raised resets it. ACK falling hands it the byte
      # on the data bus.
      class SASILines
        SEL = 0x01
        RST = 0x02
        CD = 0x04
        BSY = 0x08
        J14 = 0x10
        IO = 0x40
        MSG = 0x80

        attr_reader :target
        attr_writer :via

        # `four_heads` is J14.
        def initialize(target, four_heads:)
          @target = target
          @four_heads = four_heads
          @via = nil
          @ack_high = true
          @reset_high = false
        end

        # The data bus: the controller's byte while it drives it.
        def read_a(_lines)
          target = @target
          target.input? ? target.data : 0xff
        end

        def read_b(_lines)
          target = @target
          value = 0x23
          value |= CD if target.control?
          value |= BSY if target.busy?
          value |= J14 if @four_heads
          value |= IO if target.input?
          value |= MSG if target.message?
          value
        end

        # One cycle of the controller, then the host's ACK, RST and SEL to
        # the controller, and REQ to CA1.
        def cycle!
          target = @target
          via = @via
          target.clock
          ack_high = via.ca2_output
          target.acknowledge(via.port_a_output) if @ack_high && !ack_high
          @ack_high = ack_high
          host = via.port_b_output & via.peek(0x82)
          reset_high = host.anybits?(RST)
          target.reset if reset_high && !@reset_high
          @reset_high = reset_high
          target.select(via.port_a_output) if host.anybits?(SEL)
          via.ca1 = target.request?
        end

        # Everything the lines hold between cycles.
        def state = [@ack_high, @reset_high]

        def state=(values)
          @ack_high, @reset_high = values
        end
      end
    end
  end
end
