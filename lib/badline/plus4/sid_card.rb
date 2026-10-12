# frozen_string_literal: true

module Badline
  class Plus4
    # A SID card's SID at $FD40-$FD5F, clocked once a TED cycle, as the
    # cards clock it from the TED's single clock. The SID counts the
    # cycles that have passed whenever something touches it, rather than
    # every cycle: a CPU access runs it through the cycle the access is in,
    # and the host, between cycles, up to the cycle about to start.
    # `clock` answers the machine's cycles.
    class SIDCard
      attr_reader :sid

      def initialize(clock, model)
        @clock = clock
        @sid = Chips::SID.new(model:, at: 0xfd40)
        @clocked = 0
      end

      def model = @sid.model

      def model=(model)
        catch_up!
        @sid.model = model
      end

      def peek(addr)
        run_to(@clock.cycles + 1)
        @sid.peek(addr)
      end

      def poke(addr, value)
        run_to(@clock.cycles + 1)
        @sid.poke(addr, value)
      end

      # The RES line, from the host between cycles.
      def reset!
        run_to(@clock.cycles)
        @sid.reset!
      end

      # Runs the SID, its voices and its filter, up to the current cycle.
      def catch_up!
        run_to(@clock.cycles)
        @sid.catch_up!
      end

      def record(rate:, clock_hz:)
        run_to(@clock.cycles)
        @sid.record(rate:, clock_hz:)
      end

      def drain_samples
        run_to(@clock.cycles)
        @sid.drain_samples
      end

      # The SID's fields in a keyed snapshot module (BL-SID), saved once the
      # machine has settled it (#catch_up!).
      def save_fields(out) = @sid.save_fields(out)

      def load_fields(input)
        @sid.load_fields(input)
      end

      # The SID counts on from the machine's cycle the snapshot was taken at.
      def restored!
        @sid.restored!
        @clocked = @clock.cycles
      end

      private

      def run_to(target)
        clocked = @clocked
        return if clocked >= target

        sid = @sid
        while clocked < target
          sid.cycle!
          clocked += 1
        end
        @clocked = clocked
      end
    end
  end
end
