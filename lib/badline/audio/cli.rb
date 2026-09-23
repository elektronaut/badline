# frozen_string_literal: true

module Badline
  module Audio
    # Runs `badline-sid` once its options have parsed: picks the song and
    # its length, then plays it or renders it to a file.
    class CLI
      class Error < StandardError; end

      # `sink` builds the audio device for playback, given the rate to ask
      # for and whether it has to be exact.
      def initialize(options, out: $stdout, sink: SDLSink.method(:new))
        @options = options
        @out = out
        @sink = sink
      end

      def run
        @options.render? ? render : play
      rescue Renderer::UnknownFormatError, Storage::SIDFile::FormatError => e
        raise Error, e.message
      end

      def tune
        @tune ||= Storage::SIDFile.new(@options.tune_path)
      rescue Storage::SIDFile::FormatError => e
        raise Error, "#{@options.tune_path}: #{e.message}"
      end

      def song
        @song ||= (@options.song || tune.start_song).tap do |song|
          raise Error, "no song #{song}: the tune has #{tune.songs}" if song > tune.songs
        end
      end

      def seconds
        @seconds ||= @options.seconds || songlength || Options::FALLBACK_SECONDS
      end

      def sid_model = @options.sid_model || tune.sid_model

      private

      def renderer(rate)
        Renderer.new(tune, seconds:, song:, rate:, sid_model:).tap do |renderer|
          renderer.filter_chunk = @options.filter_chunk if @options.filter_chunk
        end
      end

      def render
        renderer = renderer(@options.rate)
        @out.puts describe
        @out.puts "Rendering #{seconds}s for the #{model_name} to #{@options.output} at #{@options.rate} Hz..."
        started = now
        renderer.render(@options.output) { |done| progress(done) }
        report(now - started)
      end

      def play
        sink = open_sink
        @out.puts describe
        @out.puts "Playing #{seconds}s on the #{model_name} at #{sink.rate} Hz. Ctrl-C stops."
        playback = Playback.new(sink, on_underrun: -> { @out.puts "\rRunning below real time, so it will stutter." })
        result = playback.play(renderer(sink.rate)) { |played| progress(played) }
        progress(seconds) if result == :finished
        @out.print "\n" unless @options.quiet?
        @out.puts(result == :finished ? "Done." : "Stopped.")
      end

      def open_sink
        @sink.call(rate: @options.rate, exact_rate: @options.rate_given?)
      rescue SDLSink::Error => e
        raise Error, "can't open the audio device: #{e.message}"
      end

      def describe
        header = [tune.name, tune.author, tune.released].reject(&:empty?).join(" / ")
        header.empty? ? "song #{song}" : "#{header} (song #{song})"
      end

      # HVSC's database is keyed by the tune's MD5 and lists one length per
      # song.
      def songlength
        path = @options.songlengths || Storage::SongLengths.locate(@options.tune_path)
        path && Storage::SongLengths.new(path).lengths(tune.md5)&.at(song - 1)
      end

      def model_name = sid_model.to_s.delete_prefix("mos")

      def progress(done)
        return if @options.quiet?

        @out.print format("\r%<done>6.1fs / %<total>.1fs", done:, total: seconds)
        @out.flush
      end

      def report(elapsed)
        @out.print "\r" unless @options.quiet?
        @out.puts format("Wrote %<path>s in %<elapsed>.1fs (%<speed>.2fx real time).",
                         path: @options.output, elapsed:, speed: seconds / elapsed)
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
