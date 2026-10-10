# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's main view: each voice's note over a scope of its own
    # output, and the mix below them. A tune on more than one SID gets a
    # row of voices for each, shrunk to fit and labelled with the SID's
    # number, and the mix split into its left and right.
    class VisualizerView
      HEIGHT = 176
      VOICE_WIDTH = 192
      VOICE_GAP = 16
      MIX_WIDTH = 608
      ROW_GAP = 4

      # The height of each voice's scope, by how many SIDs there are.
      VOICE_SCOPES = [64, 40, 28].freeze

      def initialize(painter, top)
        @painter = painter
        @top = top
        @voices = Array.new(VOICE_SCOPES.size) { |index| voice_scopes(index + 1) }
        @mix = Scope.new(painter, [SIDView::LEFT, mix_top(1), MIX_WIDTH, mix_height(1)],
                         span: 1024, range: 32_768, centred: true)
        @sides = Array.new(VOICE_SCOPES.size - 1) { |index| side_scopes(index + 2) }
      end

      def draw(history, played, clock_hz:)
        return if history.empty?

        count = history.sid_count
        count.times { |sid| draw_row(history, played, sid, clock_hz) }
        draw_mix(history, played, count)
      end

      private

      def left(voice) = SIDView::LEFT + (voice * (VOICE_WIDTH + VOICE_GAP))

      # The height of a row's notes, in glyphs twice the size for one SID.
      def note_height(count) = count == 1 ? 20 : 10

      def row_height(count) = note_height(count) + VOICE_SCOPES[count - 1] + ROW_GAP

      def row_top(count, sid) = @top + (sid * row_height(count))

      def mix_top(count) = row_top(count, count) + 4

      def mix_height(count) = @top + HEIGHT - 8 - mix_top(count)

      def voice_scopes(count)
        Array.new(count * 3) do |index|
          Scope.new(@painter, [left(index % 3), row_top(count, index / 3) + note_height(count), VOICE_WIDTH,
                               VOICE_SCOPES[count - 1]], span: 512, range: 9216, centred: true)
        end
      end

      def side_scopes(count)
        width = (MIX_WIDTH - VOICE_GAP) / 2
        Array.new(2) do |side|
          Scope.new(@painter, [SIDView::LEFT + (side * (width + VOICE_GAP)), mix_top(count), width, mix_height(count)],
                    span: 1024, range: 32_768, centred: true)
        end
      end

      def draw_row(history, played, sid, clock_hz)
        count = history.sid_count
        frame = history.frame(played, sid)
        top = row_top(count, sid)
        scopes = @voices[count - 1]
        3.times do |voice|
          color = SIDView::VOICE_COLORS[voice]
          note = SIDView.note(history.hertz(frame, voice, clock_hz))
          silent = history.level(frame, voice).zero?
          @painter.text(left(voice), top, note, silent ? SIDView::DIM : color, scale: count == 1 ? 2 : 1)
          scopes[(sid * 3) + voice].draw(history, played, (sid * 4) + voice, color)
        end
        draw_label(top, sid) if count > 1
      end

      def draw_label(top, sid)
        label = "SID #{sid + 1}"
        @painter.text(SIDView::LEFT + MIX_WIDTH - Painter.width(label), top, label, SIDView::TEXT)
      end

      def draw_mix(history, played, count)
        if count == 1
          @mix.draw(history, played, SIDHistory::MIX, SIDView::BRIGHT)
          return
        end

        sides = @sides[count - 2]
        sides[0].draw(history, played, history.left, SIDView::BRIGHT)
        sides[1].draw(history, played, history.right, SIDView::BRIGHT)
        top = mix_top(count) + 2
        @painter.text(SIDView::LEFT + 2, top, "L", SIDView::DIM)
        @painter.text(SIDView::LEFT + MIX_WIDTH - 10, top, "R", SIDView::DIM)
      end
    end
  end
end
