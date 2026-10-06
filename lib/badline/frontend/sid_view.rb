# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's detailed view of one SID: each voice's note,
    # registers and envelope over a scope of its output, then the filter (FilterView) and the scope of
    # the SID's own output. `sid` picks which of a tune's SIDs it shows, and
    # a tune on more than one gets a row of buttons above the voices that
    # pick it, which makes the view PICKER taller.
    class SIDView
      COLORS = VIC::PALETTE
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
      PICKER = 20

      SID_NAMES = ["SID 1", "SID 2", "SID 3"].freeze
      SIDS = %i[sid1 sid2 sid3].freeze

      # The nearest note to `hertz` and how many cents off it it is.
      def self.note(hertz)
        return "---" if hertz < 16.0

        midi = 69 + (12 * Math.log(hertz / 440.0) / Math.log(2))
        key = midi.round
        cents = ((midi - key) * 100).round
        name = NOTES[key % 12] + ((key / 12) - 1).to_s
        name.ljust(3) + format("%<sign>s%<cents>02d", sign: cents.negative? ? "-" : "+", cents: cents.abs)
      end

      # The view's height for a tune on `sids` SIDs.
      def self.height(sids) = sids > 1 ? HEIGHT + PICKER : HEIGHT

      def initialize(painter, buttons, top)
        @painter = painter
        @buttons = buttons
        @top = top
        @filter = FilterView.new(painter)
        @voices = Array.new(2) do |picker|
          Array.new(3) do |voice|
            Scope.new(painter, [WAVE_LEFT, top + (picker * PICKER) + (voice * VOICE_HEIGHT), WAVE_WIDTH,
                                VOICE_HEIGHT - 12], span: 512, range: 9216, centred: true)
          end
        end
        @outputs = Array.new(2) do |picker|
          Scope.new(painter, [WAVE_LEFT, top + (picker * PICKER) + (3 * VOICE_HEIGHT) + 4, WAVE_WIDTH, PANEL_HEIGHT],
                    span: 1024, range: 65_536)
        end
      end

      def draw(history, played, clock_hz:, model:, sid: 0)
        return if history.empty?

        picker = history.sid_count > 1 ? 1 : 0
        draw_picker(history.sid_count, sid) if picker == 1
        top = @top + (picker * PICKER)
        frame = history.frame(played, sid)
        3.times { |voice| draw_voice(history, frame, voice, top + (voice * VOICE_HEIGHT), clock_hz) }
        3.times { |voice| @voices[picker][voice].draw(history, played, (sid * 4) + voice, VOICE_COLORS[voice]) }
        @filter.draw(history, frame, top + (3 * VOICE_HEIGHT) + 4, model)
        @outputs[picker].draw(history, played, history.output(sid), BRIGHT)
      end

      private

      def draw_picker(sids, shown)
        x = LEFT
        sids.times do |sid|
          x += @buttons.text(x, @top, SID_NAMES[sid], SIDS[sid], on: sid == shown) + 4
        end
      end

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
    end
  end
end
