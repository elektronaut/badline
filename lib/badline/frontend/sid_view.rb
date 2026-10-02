# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's detailed view of one SID: each voice's note,
    # waveform and envelope, then the filter (FilterView) and the output's
    # scope.
    class SIDView
      COLORS = Screen::COLORS
      TEXT = COLORS[14]
      BRIGHT = COLORS[1]
      DIM = COLORS[11]
      BOX = COLORS[0]
      VOICE_COLORS = [COLORS[7], COLORS[13], COLORS[3]].freeze

      NOTES = %w[C C# D D# E F F# G G# A A# B].freeze
      WAVES = %w[TRI SAW PUL NOI].freeze
      FLAGS = %w[GATE SYNC RING TEST].freeze
      PHASES = { attack: "ATTACK", decay_sustain: "DECAY/SUSTAIN", release: "RELEASE" }.freeze

      LEFT = 16
      WAVE_LEFT = 432
      WAVE_WIDTH = 192
      VOICE_HEIGHT = 64
      PANEL_HEIGHT = 72
      HEIGHT = (3 * VOICE_HEIGHT) + PANEL_HEIGHT + 12

      # A fixed scatter of 12-bit values for noise, from a 16-bit xorshift.
      NOISE = Array.new(WAVE_WIDTH + 1) do |step|
        value = (step * 40_503) + 1
        3.times do
          value ^= (value << 7) & 0xffff
          value ^= value >> 9
          value ^= (value << 8) & 0xffff
        end
        value & 0xfff
      end.freeze

      # The nearest note to `hertz` and how many cents off it it is.
      def self.note(hertz)
        return "---" if hertz < 16.0

        midi = 69 + (12 * Math.log(hertz / 440.0) / Math.log(2))
        key = midi.round
        cents = ((midi - key) * 100).round
        name = NOTES[key % 12] + ((key / 12) - 1).to_s
        name.ljust(3) + format("%<sign>s%<cents>02d", sign: cents.negative? ? "-" : "+", cents: cents.abs)
      end

      def initialize(painter, top)
        @painter = painter
        @top = top
        @filter = FilterView.new(painter)
        @wave = Array.new((WAVE_WIDTH + 1) * 2, 0)
        @output = Scope.new(painter, [WAVE_LEFT, top + (3 * VOICE_HEIGHT) + 4, WAVE_WIDTH, PANEL_HEIGHT],
                            span: 1024, range: 65_536)
      end

      def draw(history, played, clock_hz:, model:)
        return if history.empty?

        frame = history.frame(played)
        3.times { |voice| draw_voice(history, frame, voice, @top + (voice * VOICE_HEIGHT), clock_hz) }
        @filter.draw(history, frame, @top + (3 * VOICE_HEIGHT) + 4, model)
        @output.draw(history, played, SIDHistory::MIX, BRIGHT)
      end

      private

      def draw_voice(history, frame, voice, top, clock_hz)
        base = voice * 7
        color = VOICE_COLORS[voice]
        control = history.register(frame, base + 4)
        hertz = history.hertz(frame, voice, clock_hz)
        paint = @painter
        paint.text(LEFT, top, "VOICE #{voice + 1}", color)
        paint.text(LEFT, top + 12, SIDView.note(hertz), history.level(frame, voice).zero? ? DIM : color, scale: 2)
        paint.text(LEFT + 112, top + 12, format("%<hertz>.1f HZ", hertz:), TEXT)
        draw_waves(control, top, color)
        draw_flags(history, frame, voice, control, top + 24)
        draw_envelope(history, frame, voice, top + 36, color)
        draw_wave(history, frame, voice, top, color)
      end

      def draw_waves(control, top, color)
        x = LEFT + 224
        WAVES.each_with_index do |wave, bit|
          x += @painter.text(x, top, wave, control[bit + 4] == 1 ? color : DIM) + 8
        end
      end

      def draw_flags(history, frame, voice, control, top)
        x = LEFT + 112
        FLAGS.each_with_index do |flag, bit|
          x += @painter.text(x, top, flag, control[bit] == 1 ? BRIGHT : DIM) + 8
        end
        filtered = history.register(frame, 0x17)[voice] == 1
        @painter.text(x, top, "FILT", filtered ? BRIGHT : DIM)
      end

      def draw_envelope(history, frame, voice, top, color)
        base = voice * 7
        attack_decay = history.register(frame, base + 5)
        sustain_release = history.register(frame, base + 6)
        paint = @painter
        paint.text(LEFT + 112, top, format("PW %<pw>5.1f%%", pw: pulse_width(history, frame, voice) * 100.0 / 4096),
                   TEXT)
        rates = "A#{hex(attack_decay >> 4)} D#{hex(attack_decay & 0x0f)} " \
                "S#{hex(sustain_release >> 4)} R#{hex(sustain_release & 0x0f)}"
        paint.text(LEFT + 224, top, rates, TEXT)
        paint.box(LEFT, top + 12, 128, 6, BOX)
        paint.box(LEFT, top + 12, history.level(frame, voice) / 2, 6, color)
        paint.box(LEFT + ((sustain_release >> 4) * 17 / 2), top + 10, 1, 10, BRIGHT)
        paint.text(LEFT + 136, top + 12, PHASES.fetch(history.state(frame, voice), ""), DIM)
      end

      def hex(nibble) = nibble.to_s(16).upcase

      def pulse_width(history, frame, voice)
        history.register(frame, (voice * 7) + 2) | ((history.register(frame, (voice * 7) + 3) & 0x0f) << 8)
      end

      # The shape the waveform bits select, two periods of it, scaled by the
      # envelope. Noise is drawn as a scatter that stays put.
      def draw_wave(history, frame, voice, top, color)
        control = history.register(frame, (voice * 7) + 4)
        pulse = pulse_width(history, frame, voice)
        level = history.level(frame, voice)
        height = VOICE_HEIGHT - 12
        middle = top + (height / 2)
        @painter.box(WAVE_LEFT, top, WAVE_WIDTH, height, BOX)
        points = @wave
        x = 0
        while x <= WAVE_WIDTH
          value = shape(control, pulse, (x * 2 * 4096 / WAVE_WIDTH) % 4096, x)
          points[x * 2] = WAVE_LEFT + x
          points[(x * 2) + 1] = middle - (((value - 2048) * level * (height - 4)) / (4096 * 255))
          x += 1
        end
        @painter.polyline(points, color)
      end

      # The 12-bit output of the waveforms selected at `phase`: those chosen
      # together are ANDed, as the chip combines them.
      def shape(control, pulse, phase, step)
        return 4095 if control.anybits?(0x08)
        return 2048 if control.nobits?(0xf0)

        value = 4095
        4.times { |bit| value &= wave(bit, phase, pulse, step) if control[bit + 4] == 1 }
        value
      end

      # Triangle, sawtooth, pulse or noise, by their bit in the control
      # register.
      def wave(bit, phase, pulse, step)
        case bit
        when 0 then phase < 2048 ? phase * 2 : (4095 - phase) * 2
        when 1 then phase
        when 2 then phase >= pulse ? 4095 : 0
        else NOISE[step]
        end
      end
    end
  end
end
