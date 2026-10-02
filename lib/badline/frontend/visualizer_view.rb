# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's main view: each voice's note over a scope of its own
    # output, and the mix below them.
    class VisualizerView
      HEIGHT = 176
      VOICE_WIDTH = 192
      VOICE_GAP = 16
      VOICE_SCOPE = 64

      def initialize(painter, top)
        @painter = painter
        @top = top
        @voices = Array.new(3) do |voice|
          Scope.new(painter, [left(voice), top + 20, VOICE_WIDTH, VOICE_SCOPE], span: 512, range: 9216, centred: true)
        end
        @mix = Scope.new(painter, [SIDView::LEFT, top + VOICE_SCOPE + 28, 608, HEIGHT - VOICE_SCOPE - 36],
                         span: 1024, range: 32_768, centred: true)
      end

      def draw(history, played, clock_hz:)
        return if history.empty?

        frame = history.frame(played)
        3.times { |voice| draw_voice(history, frame, played, voice, clock_hz) }
        @mix.draw(history, played, SIDHistory::MIX, SIDView::BRIGHT)
      end

      private

      def left(voice) = SIDView::LEFT + (voice * (VOICE_WIDTH + VOICE_GAP))

      def draw_voice(history, frame, played, voice, clock_hz)
        color = SIDView::VOICE_COLORS[voice]
        hertz = history.hertz(frame, voice, clock_hz)
        silent = history.level(frame, voice).zero?
        @painter.text(left(voice), @top, SIDView.note(hertz), silent ? SIDView::DIM : color, scale: 2)
        @voices[voice].draw(history, played, voice, color)
      end
    end
  end
end
