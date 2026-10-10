# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's INFO view: the tune's STIL entry, and the playing
    # subtune's, laid out as STIL.txt lays them out but reflowed to the
    # window's width. A line of STIL's that runs to its width goes on into
    # the next, and a shorter one ends a paragraph. Text longer than the view
    # scrolls, by the wheel, the up and down keys, or a click or drag along
    # the scroll bar beside it.
    class InfoView
      HEIGHT = VisualizerView::HEIGHT
      LINE = 10
      ROWS = HEIGHT / LINE
      LEFT = SIDView::LEFT
      BAR = 6
      BAR_LEFT = PlayerHeader::WIDTH - 16 - BAR
      COLUMNS = (BAR_LEFT - LEFT - 8) / Painter::GLYPH
      LABEL = 9

      # How long a line of STIL's is when it runs on into the next.
      FULL = 60

      attr_reader :offset

      def initialize(painter, buttons, top)
        @painter = painter
        @buttons = buttons
        @top = top
        @lines = []
        @offset = 0
      end

      # Shows the tune's fields, then the subtune's under its number, from
      # the top.
      def show(fields, subtune, subtune_fields)
        lines = InfoView.layout(fields)
        lines += ["", "(##{subtune})"] + InfoView.layout(subtune_fields) unless subtune_fields.empty?
        @lines = lines.empty? ? ["No STIL entry for this tune."] : lines
        @offset = 0
      end

      def scroll(rows)
        @offset = (@offset + rows).clamp(0, last_offset)
      end

      # Scrolls to the place `top` points at along the scroll bar.
      def scroll_along(top)
        @offset = ((top - @top).to_f / HEIGHT * @lines.size).round.clamp(0, last_offset)
      end

      def draw
        index = 0
        while index < ROWS && @offset + index < @lines.size
          @painter.text(LEFT, @top + (index * LINE), @lines[@offset + index], PlayerTheme::TEXT)
          index += 1
        end
        draw_bar if @lines.size > ROWS
      end

      # Each field's label, right-aligned as in STIL.txt, before its text
      # reflowed into the columns beside it.
      def self.layout(fields)
        lines = []
        fields.each do |field|
          label = "#{field.name}:".rjust(LABEL - 1)
          paragraphs(field.text).each do |paragraph|
            wrap(paragraph, COLUMNS - LABEL).each do |line|
              lines << "#{label} #{line}"
              label = " " * (LABEL - 1)
            end
          end
        end
        lines
      end

      # The text's lines joined where one ran to STIL's width.
      def self.paragraphs(text)
        paragraphs = []
        full = false
        text.split("\n").each do |line|
          if full
            paragraphs[-1] = "#{paragraphs[-1]} #{line.strip}"
          else
            paragraphs << line.strip
          end
          full = line.length >= FULL
        end
        paragraphs
      end

      # The text broken at spaces into lines of at most `columns`, and a word
      # longer than that broken where it has to be.
      def self.wrap(text, columns)
        lines = []
        rest = text
        while rest.length > columns
          cut = rest.rindex(" ", columns)
          cut = columns if cut.nil? || cut.zero?
          lines << rest[0, cut].rstrip
          rest = rest[cut, rest.length - cut].lstrip
        end
        lines << rest
        lines
      end

      private

      def last_offset = [@lines.size - ROWS, 0].max

      def draw_bar
        @buttons.area([BAR_LEFT, @top, BAR, HEIGHT], :scroll)
        @painter.box(BAR_LEFT, @top, BAR, HEIGHT, PlayerTheme::BOX)
        thumb = [HEIGHT * ROWS / @lines.size, 8].max
        place = (HEIGHT - thumb) * @offset / [last_offset, 1].max
        @painter.box(BAR_LEFT, @top + place, BAR, thumb, PlayerTheme::TEXT)
      end
    end
  end
end
