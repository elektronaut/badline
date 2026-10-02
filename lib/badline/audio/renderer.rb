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
      # still count up to it. Rendering picks up from the latest of the
      # checkpoints at or before it, without the frames before that.
      attr_writer :from

      # The Checkpoints this subtune's renderers keep as they go and start
      # from.
      attr_writer :checkpoints

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
        @checkpoints = Checkpoints.new
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
        container.open(path, rate: @rate) do |writer|
          each_frame do |samples, seconds|
            samples.each { |sample| writer << sample }
            yield seconds if block_given?
          end
        end
      end

      # Starts the tune, then yields each frame's samples along with the
      # seconds rendered so far.
      def stream(&) = each_frame(&)

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
        clock_hz = player.clock_hz
        total = total_cycles
        skipped = (@from * clock_hz).round
        remaining = total - start(skipped)
        while remaining.positive?
          samples = []
          remaining -= player.frame(remaining) { |sample| samples << sample }
          played = total - remaining
          @rendered = played.fdiv(clock_hz)
          @observer.call(samples, @rendered)
          yield(played < skipped ? [] : samples, @rendered)
          break if fallen_silent?(samples)

          save_checkpoint(played) if @checkpoints.due?(played, clock_hz)
        end
      end

      # Starts the player and its recording, from the latest checkpoint at
      # or before `cycles` if there is one, and returns the cycles into the
      # subtune it starts at.
      def start(cycles)
        state = @checkpoints.latest(cycles)
        return start_afresh if state.nil?

        input = Snapshot::StateReader.new(state)
        played = input.int
        resume(input)
        record
        player.sid.load_recording(input)
        @level = input.int
        @still = input.int
        played
      end

      def start_afresh
        player.start
        record
        0
      end

      def record = player.sid.record(rate: @rate, filter_chunk: @filter_chunk, clock_hz: player.clock_hz)

      # Restores the player as it was, then puts back the SID model chosen
      # for this renderer.
      def resume(input)
        sid = player.sid
        chosen = sid.model
        saved = Snapshot::Setup::SID_MODELS.fetch(input.int)
        sid.model = saved unless saved == chosen
        player.load_state(input)
        sid.model = chosen unless sid.model == chosen
      end

      def save_checkpoint(played)
        sid = player.sid
        out = Snapshot::StateWriter.new
        out.int(played).int(Snapshot::Setup::SID_MODELS.index(sid.model) || 0)
        player.save_state(out)
        sid.save_recording(out)
        out.int(@level).int(@still)
        @checkpoints.keep(played, out.state)
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
