# frozen_string_literal: true

module Badline
  module Audio
    # Renders a .sid tune to a PCM file, or streams its samples to whoever
    # plays them. A PSID tune with a play address runs on the bare rig;
    # anything else drives its own interrupts and needs the whole machine.
    #
    # A .sid file carries no length, so the caller says how many seconds to
    # render. For a tune whose length is a guess, #silence= also ends it
    # once the output has held still for that many seconds.
    class Renderer
      class UnknownFormatError < StandardError; end

      DEFAULT_RATE = 44_100

      # How far a sample may stray from where the output settled and still
      # count as silence. A 6581 settles at a DC offset rather than at zero.
      QUIET = 16

      CONTAINERS = { ".wav" => WAV, ".aiff" => AIFF, ".aif" => AIFF }.freeze

      # The cycles the SID's filter integrates at a time; 1 renders the
      # filter cycle by cycle, exactly.
      attr_writer :filter_chunk

      # The seconds rendered so far, short of the length once the tune has
      # fallen silent.
      attr_reader :rendered, :tune, :rate

      # Hears each frame's samples and the seconds rendered by its end, as
      # they are rendered.
      attr_writer :observer

      # Where #stream starts: the frames before it are rendered as fast as
      # they go and yielded without their samples, so the seconds rendered
      # still count up to it.
      attr_writer :from

      def initialize(tune, seconds:, subtune: nil, rate: DEFAULT_RATE, sid_model: tune.sid_model)
        @tune = tune
        @seconds = seconds
        @subtune = subtune
        @rate = rate
        @sid_model = sid_model
        @filter_chunk = SID::FILTER_CHUNK
        @silent_samples = 0
        @level = 0
        @still = 0
        @rendered = 0.0
        @observer = ->(_samples, _rendered) {}
        @from = 0.0
      end

      def silence=(seconds)
        @silent_samples = (seconds * @rate).round
      end

      def player
        @player ||= (bare? ? BarePlayer : MachinePlayer).new(@tune, subtune: @subtune, sid_model: @sid_model)
      end

      # Yields the seconds rendered so far after every frame.
      def render(path)
        container = container_for(path)
        player.start
        container.open(path, rate: @rate) do |writer|
          each_frame do |samples, seconds|
            samples.each { |sample| writer << sample }
            yield seconds if block_given?
          end
        end
      end

      # Starts the tune, then yields each frame's samples along with the
      # seconds rendered so far.
      def stream(&)
        player.start
        each_frame(&)
      end

      private

      def bare? = @tune.format == "PSID" && @tune.play_address.positive?

      def total_samples = (@seconds * @rate).round

      # The cycles it takes to close exactly `total_samples` windows; the SID
      # records floor(cycles * rate / clock) of them.
      def total_cycles
        ((total_samples * player.clock_hz) + @rate - 1) / @rate
      end

      def container_for(path)
        extension = File.extname(path).downcase
        CONTAINERS.fetch(extension) do
          raise UnknownFormatError, "Unknown output format: #{extension}"
        end
      end

      def each_frame
        player.sid.record(rate: @rate, filter_chunk: @filter_chunk, clock_hz: player.clock_hz)
        total = total_cycles
        remaining = total
        skipped = (@from * player.clock_hz).round
        while remaining.positive?
          samples = []
          remaining -= player.frame(remaining) { |sample| samples << sample }
          @rendered = (total - remaining).fdiv(player.clock_hz)
          @observer.call(samples, @rendered)
          yield(total - remaining < skipped ? [] : samples, @rendered)
          break if fallen_silent?(samples)
        end
      end

      # Counts the samples since the output last strayed more than QUIET
      # from where it settled.
      def fallen_silent?(samples)
        return false if @silent_samples.zero? || samples.empty?

        if samples.max - @level > QUIET || @level - samples.min > QUIET
          @level = samples.last
          @still = 0
        else
          @still += samples.length
        end
        @still >= @silent_samples
      end
    end
  end
end
