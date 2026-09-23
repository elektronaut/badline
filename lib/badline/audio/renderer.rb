# frozen_string_literal: true

module Badline
  module Audio
    # Renders a .sid tune to a PCM file, or streams its samples to whoever
    # plays them. A PSID tune with a play address runs on the bare rig;
    # anything else drives its own interrupts and needs the whole machine.
    #
    # A .sid file carries no length, so the caller says how many seconds to
    # render.
    class Renderer
      class UnknownFormatError < StandardError; end

      DEFAULT_RATE = 44_100

      CONTAINERS = { ".wav" => WAV, ".aiff" => AIFF, ".aif" => AIFF }.freeze

      # The cycles the SID's filter integrates at a time; 1 renders the
      # filter cycle by cycle, exactly.
      attr_writer :filter_chunk

      def initialize(tune, seconds:, song: nil, rate: DEFAULT_RATE, sid_model: tune.sid_model)
        @tune = tune
        @seconds = seconds
        @song = song
        @rate = rate
        @sid_model = sid_model
        @filter_chunk = SID::FILTER_CHUNK
      end

      def player
        @player ||= (bare? ? BarePlayer : MachinePlayer).new(@tune, song: @song, sid_model: @sid_model)
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
        ((total_samples * TimeOfDay::CLOCK_HZ) + @rate - 1) / @rate
      end

      def container_for(path)
        extension = File.extname(path).downcase
        CONTAINERS.fetch(extension) do
          raise UnknownFormatError, "Unknown output format: #{extension}"
        end
      end

      def each_frame
        player.sid.record(rate: @rate, filter_chunk: @filter_chunk)
        total = total_cycles
        remaining = total
        while remaining.positive?
          samples = []
          remaining -= player.frame(remaining) { |sample| samples << sample }
          yield samples, (total - remaining).fdiv(TimeOfDay::CLOCK_HZ)
        end
      end
    end
  end
end
