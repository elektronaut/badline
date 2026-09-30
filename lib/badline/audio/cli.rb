# frozen_string_literal: true

module Badline
  module Audio
    # Runs `--headless` or `--audio-out`, in either build, once its options
    # have parsed: picks the song and its length, then plays it or renders
    # it to a file. Played on a terminal, it plays a queue of the tune's
    # songs, and the console lets the listener step through it.
    class CLI
      class Error < StandardError; end

      # Plays or renders the tune as #run does, reports an error on stderr
      # under the program's name, and returns the exit status.
      def self.run(options, sink:, console:)
        new(options, sink:, console:).run
        0
      rescue Error => e
        warn "#{options.program}: #{e.message}"
        1
      rescue Interrupt
        130
      end

      # Playing needs `sink`, which builds the audio device given the rate
      # to ask for and whether it has to be exact, and, on a terminal,
      # `console`, which builds the terminal to play on given the input and
      # output. Each build's entry point hands them in: both builds' sink is
      # Frontend::AudioSink, and the console is badline-ruby's Console or
      # the native badline's Native::Console.
      def initialize(options, sink: nil, console: nil, out: $stdout, input: $stdin)
        @options = options
        @out = out
        @input = input
        @sink = sink
        @console = console
        @lengths = {}
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

      def seconds = length(song)

      def length(song)
        @lengths[song] ||= @options.seconds || songlength(song) || @options.fallback_seconds
      end

      def sid_model = @options.sid_model || tune.sid_model

      def interactive? = @options.tui? && @input.tty? && @out.tty?

      private

      def renderer(song, rate)
        Renderer.new(tune, seconds: length(song), song:, rate:, sid_model:).tap do |renderer|
          renderer.filter_chunk = @options.filter_chunk if @options.filter_chunk
        end
      end

      def render
        renderer = renderer(song, @options.rate)
        @out.puts describe
        @out.puts "Rendering #{seconds}s for the #{model_name} to #{@options.audio_out} at #{@options.rate} Hz..."
        started = now
        renderer.render(@options.audio_out) { |done| progress(done) }
        report(now - started)
      end

      def play
        sink = open_sink
        interactive? ? play_interactively(sink) : play_plainly(sink)
      ensure
        sink&.close
      end

      def play_plainly(sink)
        @out.puts describe
        @out.puts "Playing #{seconds}s on the #{model_name} at #{sink.rate} Hz. Ctrl-C stops."
        playback = Playback.new(sink, on_underrun: -> { @out.puts "\rRunning below real time, so it will stutter." })
        result = playback.play(renderer(song, sink.rate)) { |played| progress(played) }
        progress(seconds) if result == :finished
        @out.print "\n" unless @options.quiet?
        @out.puts(result == :finished ? "Done." : "Stopped.")
      end

      def play_interactively(sink)
        console = @console.call(input: @input, output: @out)
        queue = Media::Queue.new([Media::Queue::Entry.new(@options.tune_path, part: song, parts: tune.songs)])
        jukebox = Jukebox.new(sink, console, queue:, renderer: ->(_entry, song, rate) { renderer(song, rate) },
                                             length: ->(_entry, song) { length(song) })
        console.session do
          console.header([tune.name, tune.author, tune.released].reject(&:empty?) +
                         ["#{model_name} at #{sink.rate} Hz"])
          jukebox.run
        end
      end

      def open_sink
        @sink.call(rate: @options.rate, exact_rate: @options.rate_given?)
      rescue Playback::DeviceError => e
        raise Error, "can't open the audio device: #{e.message}"
      end

      def describe
        header = [tune.name, tune.author, tune.released].reject(&:empty?).join(" / ")
        header.empty? ? "song #{song}" : "#{header} (song #{song})"
      end

      # HVSC's database is keyed by the tune's MD5 and lists one length per
      # song.
      def songlength(song) = songlengths&.at(song - 1)

      def songlengths
        return @songlengths if @songlengths_read

        @songlengths_read = true
        path = @options.songlengths || Storage::SongLengths.locate(@options.tune_path)
        @songlengths = path && Storage::SongLengths.new(path).lengths(tune.md5)
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
                         path: @options.audio_out, elapsed:, speed: seconds / elapsed)
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
