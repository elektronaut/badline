# frozen_string_literal: true

module Badline
  module Audio
    # The SIDs a tune plays on, the bus's own first and the extra ones at
    # the addresses the tune's header gives, each on its own model. Their
    # output mixes to interleaved stereo: SID 1 on the left, SID 2 on the
    # right and SID 3 in the centre, at half on each side. A tune on one SID
    # plays the same on both channels.
    class Stereo
      # The SIDs, in the order the header numbers them.
      attr_reader :sids

      # Each SID's own samples, as the last #mix drained them.
      attr_reader :outputs

      def initialize(bus, tune, models)
        @sids = [bus.sid]
        @extras = []
        tune.sid_addresses.each do |address|
          sid = SID.new(model: models[@sids.size], at: address)
          bus.add_sid(sid)
          @sids << sid
          @extras << sid
        end
        @fitted = models
        @outputs = []
      end

      # The SIDs past the bus's own, which the player clocks itself.
      attr_reader :extras

      def synthesize! = @sids.each(&:synthesize!)

      # The model each SID plays on.
      def models = @sids.map(&:model)

      # Puts every SID on `model`, or with :auto each back on the one it was
      # fitted with.
      def refit(model)
        @sids.size.times do |index|
          wanted = model == :auto ? @fitted[index] : model
          sid = @sids[index]
          sid.model = wanted unless sid.model == wanted
        end
      end

      def record(rate:, filter_chunk:, clock_hz:)
        @sids.each { |sid| sid.record(rate:, filter_chunk:, clock_hz:) }
      end

      # Drains every SID and yields the left and the right of each sample
      # in turn.
      def mix(&)
        outputs = @outputs
        outputs.clear
        @sids.each { |sid| outputs << sid.drain_samples }
        case outputs.size
        when 1 then both(outputs[0], &)
        when 2 then pair(outputs[0], outputs[1], &)
        else centred(outputs[0], outputs[1], outputs[2], &)
        end
      end

      private

      def both(samples)
        i = 0
        while i < samples.size
          yield samples[i]
          yield samples[i]
          i += 1
        end
      end

      def pair(left, right)
        count = [left.size, right.size].min
        i = 0
        while i < count
          yield left[i]
          yield right[i]
          i += 1
        end
      end

      def centred(left, right, centre)
        count = [left.size, right.size, centre.size].min
        i = 0
        while i < count
          yield ((2 * left[i]) + centre[i]) / 3
          yield ((2 * right[i]) + centre[i]) / 3
          i += 1
        end
      end
    end
  end
end
