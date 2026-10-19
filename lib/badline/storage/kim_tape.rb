# frozen_string_literal: true

module Badline
  module Storage
    # A KIM-1 cassette, held as the times its signal crosses zero, in
    # microseconds from the start of the tape, which are the KIM-1's
    # cycles. The KIM-1 writes the tape as a square wave on U2's PB7, each
    # bit 3,700 Hz then 2,400 Hz, and reads it back through a 565 PLL and a
    # 311 comparator, which hold PB7 high through the 2,400 Hz tone and low
    # through the 3,700 Hz one (User Manual, appendix E). edges gives the
    # times PB7 changes as the tape plays.
    #
    # A tape reads from a .wav file, 8-bit or 16-bit PCM, its first
    # channel only, and writes one back as a square wave.
    class KIMTape
      class FormatError < StandardError; end

      # A period longer than this many microseconds is the 2,400 Hz tone:
      # the split between the tones, at the geometric mean of the two.
      SPLIT = 336

      # The time constants, in seconds, of the detector's DC level and of
      # its envelope, which sets the hysteresis.
      DC_TIME = 0.002
      ENVELOPE_TIME = 0.005

      # The signal crosses the DC level once it swings this fraction of the
      # envelope past it, and not for an envelope smaller than SILENCE, of
      # full scale.
      HYSTERESIS = 0.3
      SILENCE = 0.03

      # A gap this many microseconds long between crossings plays as
      # silence in the .wav a tape writes.
      GAP = 2_000

      # The file the tape reads from and writes back to, or "" for none.
      attr_reader :path, :crossings

      # The tape in the .wav file at `path`.
      def self.read(path) = new(path, crossings: from_wav(File.binread(path).bytes))

      # A blank tape at `path`, written to the host file.
      def self.create(path)
        tape = new(path)
        tape.save
        tape
      end

      # The zero crossings of the .wav file in `bytes`.
      def self.from_wav(bytes)
        raise FormatError, "Not a RIFF WAVE file" unless bytes[0, 4] == "RIFF".bytes && bytes[8, 4] == "WAVE".bytes

        format = nil
        pos = 12
        while pos + 8 <= bytes.length
          id = bytes[pos, 4].pack("C*")
          size = little_endian(bytes, pos + 4, 4)
          format = bytes[pos + 8, 16] if id == "fmt "
          return Detector.new(Format.new(format)).crossings(bytes, pos + 8, size) if id == "data" && format

          pos += 8 + size + (size & 1)
        end
        raise FormatError, "No PCM data in the WAVE file"
      end

      def self.little_endian(bytes, pos, count)
        value = 0
        count.times { |i| value |= bytes[pos + i].to_i << (8 * i) }
        value
      end

      def initialize(path = "", crossings: [])
        @path = path
        @crossings = crossings
      end

      # The time of the last crossing.
      def duration = @crossings.empty? ? 0 : @crossings.last

      # Erases the tape from `time` on, as a deck recording from there
      # does.
      def erase_from(time)
        @crossings.pop while !@crossings.empty? && @crossings.last >= time
      end

      # Records a crossing at `time`, after the last one.
      def record(time)
        @crossings << time
      end

      # The times PB7 changes as the tape plays, from high at its start: to
      # low where a period is the 3,700 Hz tone and back to high where one
      # is the 2,400 Hz tone. Each period runs over two crossings, and two
      # in a row must agree before PB7 follows, so that one crossing out of
      # place doesn't split a bit. The period that straddles the change
      # lies between the tones, so PB7 changes half way through it.
      def edges
        crossings = @crossings
        edges = []
        high = true
        disagree = 0
        i = 2
        while i < crossings.length
          low_tone = crossings[i] - crossings[i - 2] > SPLIT
          if low_tone == high
            disagree = 0
          else
            disagree += 1
            if disagree == 2
              high = low_tone
              edges << ((crossings[i - 3] + crossings[i - 2]) / 2)
              disagree = 0
            end
          end
          i += 1
        end
        edges
      end

      # Writes the tape back to its host file.
      def save
        write_wav(@path)
      end

      # Writes the tape to `path` as a .wav file, a square wave of `bits`
      # (8 or 16) at `rate` samples a second.
      def write_wav(path, rate: 44_100, bits: 8)
        samples = square_wave(rate, bits == 8 ? 96 : 24_000)
        bytes = bits == 8 ? samples.map { |sample| sample + 128 } : samples.flat_map { |s| [s & 0xff, (s >> 8) & 0xff] }
        File.binwrite(path, (wav_header(rate, bits, bytes.length) + bytes).pack("C*"))
      end

      private

      # The tape as samples of `amplitude`: silent up to the first
      # crossing, after a GAP and at the end, and otherwise each crossing
      # turning the wave over.
      def square_wave(rate, amplitude)
        samples = []
        crossings = @crossings
        count = crossings.empty? ? 0 : (((crossings.last + GAP) * rate) / 1_000_000) + 1
        index = 0
        level = -amplitude
        count.times do |n|
          time = (n * 1_000_000) / rate
          while index < crossings.length && crossings[index] <= time
            level = -level
            index += 1
          end
          samples << (index.zero? || time - crossings[index - 1] > GAP ? 0 : level)
        end
        samples
      end

      def wav_header(rate, bits, size)
        bytes_per_sample = bits / 8
        "RIFF".bytes + le(36 + size, 4) + "WAVEfmt ".bytes + le(16, 4) + le(1, 2) + le(1, 2) +
          le(rate, 4) + le(rate * bytes_per_sample, 4) + le(bytes_per_sample, 2) + le(bits, 2) +
          "data".bytes + le(size, 4)
      end

      def le(value, count) = Array.new(count) { |i| (value >> (8 * i)) & 0xff }

      # A WAVE file's fmt chunk: PCM, 8-bit unsigned or 16-bit signed.
      class Format
        attr_reader :channels, :rate, :bits

        def initialize(chunk)
          tag = KIMTape.little_endian(chunk, 0, 2)
          @channels = KIMTape.little_endian(chunk, 2, 2)
          @rate = KIMTape.little_endian(chunk, 4, 4)
          @bits = KIMTape.little_endian(chunk, 14, 2)
          return if [1, 0xfffe].include?(tag) && [8, 16].include?(@bits) && @channels.positive?

          raise FormatError, "Only 8-bit and 16-bit PCM WAVE files are supported"
        end

        def frame_size = @channels * @bits / 8

        # The first channel's sample at `pos`, from -1 to 1.
        def level_at(bytes, pos)
          return (bytes[pos] - 128) / 128.0 if @bits == 8

          value = bytes[pos] | (bytes[pos + 1] << 8)
          (value >= 0x8000 ? value - 0x10000 : value) / 32_768.0
        end
      end

      # Finds where a recording crosses zero. A cassette's signal wanders
      # off its centre and fades, so the detector follows its DC level and
      # its envelope, and counts a crossing only once the signal swings past
      # the DC level by HYSTERESIS of the envelope, timing it where it
      # crossed the DC level, between two samples.
      class Detector
        def initialize(format)
          @format = format
          rate = format.rate
          @dc_step = 1.0 / (rate * DC_TIME)
          @decay = Math.exp(-1.0 / (rate * ENVELOPE_TIME))
          @scale = 1_000_000.0 / rate
          @dc = @envelope = @previous = @rose = @fell = 0.0
          @high = false
          @found = []
        end

        # The crossings, in microseconds, of the samples in `bytes` from
        # `pos`, `size` bytes of them.
        def crossings(bytes, pos, size)
          format = @format
          frame = format.frame_size
          last = [pos + size, bytes.length].min - frame
          n = 0
          while pos <= last
            follow(format.level_at(bytes, pos), n)
            pos += frame
            n += 1
          end
          @found
        end

        private

        # Takes the sample `sample`, the `index`th.
        def follow(sample, index)
          @dc += (sample - @dc) * @dc_step
          level = sample - @dc
          @envelope *= @decay
          @envelope = level.abs if level.abs > @envelope
          previous = @previous
          if previous <= 0 && level.positive?
            @rose = index - 1 + (previous / (previous - level))
          elsif previous >= 0 && level.negative?
            @fell = index - 1 + (previous / (previous - level))
          end
          @previous = level
          swing(level) if @envelope > SILENCE
        end

        # Turns over at a `level` far enough past the DC level.
        def swing(level)
          swing = @envelope * HYSTERESIS
          if !@high && level > swing
            @high = true
            @found << (@rose * @scale).round
          elsif @high && level < -swing
            @high = false
            @found << (@fell * @scale).round
          end
        end
      end
    end
  end
end
