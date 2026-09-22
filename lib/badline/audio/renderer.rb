# frozen_string_literal: true

module Badline
  module Audio
    # Renders a .sid tune to a PCM file. A PSID tune with a play address runs
    # on the bare rig; anything else drives its own interrupts and needs the
    # whole machine.
    #
    # A .sid file carries no length, so the caller says how many seconds to
    # render.
    class Renderer
      class UnknownFormatError < StandardError; end

      DEFAULT_RATE = 44_100

      CONTAINERS = { ".wav" => WAV, ".aiff" => AIFF, ".aif" => AIFF }.freeze

      def initialize(tune, seconds:, song: nil, rate: DEFAULT_RATE, sid_model: tune.sid_model)
        @tune = tune
        @seconds = seconds
        @song = song
        @rate = rate
        @sid_model = sid_model
      end

      def player
        @player ||= (bare? ? BarePlayer : MachinePlayer).new(@tune, song: @song, sid_model: @sid_model)
      end

      # Yields the seconds rendered so far after every frame.
      def render(path, &)
        container = container_for(path)
        player.start
        container.open(path, rate: @rate) { |writer| run(writer, &) }
      end

      private

      def bare? = @tune.format == "PSID" && @tune.play_address.positive?

      def total_samples = (@seconds * @rate).round

      # The cycles it takes to close exactly `total_samples` windows; the
      # decimator emits floor(cycles * rate / clock) of them.
      def total_cycles
        ((total_samples * TimeOfDay::CLOCK_HZ) + @rate - 1) / @rate
      end

      def container_for(path)
        extension = File.extname(path).downcase
        CONTAINERS.fetch(extension) do
          raise UnknownFormatError, "Unknown output format: #{extension}"
        end
      end

      def run(writer)
        decimator = Decimator.new(clock_hz: TimeOfDay::CLOCK_HZ, rate: @rate)
        total = total_cycles
        remaining = total
        while remaining.positive?
          remaining -= player.frame(remaining) do |sample|
            decimated = decimator.push(sample)
            writer << decimated if decimated
          end
          yield((total - remaining).fdiv(TimeOfDay::CLOCK_HZ)) if block_given?
        end
      end
    end
  end
end
