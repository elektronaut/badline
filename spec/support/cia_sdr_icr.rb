# frozen_string_literal: true

# CIA/shiftregister/cia-sdr-icr from VICE-testprogs, offline. The program
# starts timer A with the shift register in output mode, loads the SDR and
# samples the ICR twice per iteration: 4 cycles after the SDR write
# (results2) and 20 + i cycles later on sample i (results1).
#
# Reference is a port of check1/check2 in cia-sdr-icr-v3.asm, the code the
# programs run. generate.c is not a faithful copy: its reset1 sets
# delaysetsdr1 to the baud for every baud, where the .asm keeps 3 for bauds
# of 3 and up.
module CiaSdrIcr
  SAMPLES = 1000
  INT_TA = 0x01
  INT_SDR = 0x08

  # reference1/reference2 for one baud (timer A latch) and CIA type:
  # :normal, :generic or :c4485. nil marks a sample the generic test skips.
  module Reference
    module_function

    def results1(baud)
      set = Set1.new(baud)
      29.times { set.step }
      Array.new(SAMPLES) { set.step }
    end

    def results2(baud, type)
      set = Set2.new(baud, type)
      (baud == 2 ? 37 : 40).times { set.step }
      Array.new(SAMPLES) { set.step }
    end

    # check1
    class Set1
      def initialize(baud)
        @baud = baud
        @count = baud
        @delaysetsdr = baud < 3 ? baud | 0x04 : 0x03
        @expected = 0x00
        @newvalue = INT_TA
        @bits = 0x0f
      end

      def step
        return INT_TA if @baud.zero?

        @count -= 1
        underflow if @count.negative?
        @expected
      end

      private

      def underflow
        @count = @baud
        @expected = @newvalue
        @bits = (@bits - 1) & 0xff
        return unless @bits.zero?

        @newvalue = INT_TA | INT_SDR
        @count = @delaysetsdr
      end
    end

    # check2
    class Set2
      def initialize(baud, type)
        @baud = baud
        @count = baud
        @clearmask = baud < 6 ? 0xff : 0xff & ~INT_TA
        @expected = 0x00
        @clearsdrdelay = @delaysetsdr = @ignore = 0x00
        @bits = 0x0f
        @sdrpipe = 0x14
        @sdrfinal = type == :c4485 ? 0x08 : 0x04
        @bouncesdr = type == :c4485 ? 0x00 : INT_SDR
        @generic = type == :generic
      end

      def step
        return INT_TA | INT_SDR if @baud.zero?

        @count -= 1
        @count.negative? ? underflow : (@expected &= @clearmask)
        skipped = shift_delays
        skipped ? nil : @expected
      end

      private

      def underflow
        @count = @baud
        @expected |= INT_TA
        return @clearsdrdelay |= 0x02 if @bits.zero?

        @bits -= 1
        @sdrpipe = @sdrfinal if @bits.zero?
        return @clearsdrdelay |= 0x02 if @bits.odd?

        if @generic
          @ignore |= @bouncesdr
        else
          @clearsdrdelay |= @bouncesdr
        end
        @delaysetsdr |= @sdrpipe
      end

      # The three delay lines shift left once per cycle; a bit leaving the
      # top clears the SDR flag, sets it, or skips the sample.
      def shift_delays
        @expected &= ~INT_SDR if @clearsdrdelay.anybits?(0x80)
        @clearsdrdelay = (@clearsdrdelay << 1) & 0xff
        @expected |= INT_SDR if @delaysetsdr.anybits?(0x80)
        @delaysetsdr = (@delaysetsdr << 1) & 0xff
        skipped = @ignore.anybits?(0x80)
        @ignore = (@ignore << 1) & 0xff
        skipped
      end
    end
  end

  # The program's test loop against a bare CIA 1: [results1, results2].
  module Replay
    module_function

    def run(baud)
      cia = Badline::CIA.new
      [[0x0e, 0x00], [0x0f, 0x00], [0x04, baud], [0x05, 0x00], [0x0d, 0x7f]].each { |reg, value| cia.poke(reg, value) }
      # The first call's result is discarded; sample i waits 20 + i cycles.
      test(cia, 19)
      Array.new(SAMPLES) { |i| test(cia, 20 + i) }.transpose
    end

    def test(cia, delay)
      icr(cia, 4)
      step(cia, 4)
      cia.poke(0x0e, 0x51) # start TA, force load, SDR output
      step(cia, 4)
      cia.poke(0x0c, 0x55)
      results2 = icr(cia, 4)
      results1 = icr(cia, 4 + delay)
      step(cia, 10)
      cia.poke(0x0e, cia.peek(0x0e) & 0x80)
      step(cia, 40) # the loop around the next call
      [results1, results2]
    end

    def icr(cia, cycles)
      step(cia, cycles)
      cia.peek(0x0d) & 0x1f
    end

    def step(cia, cycles) = cycles.times { cia.cycle! }
  end
end
