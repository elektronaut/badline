# frozen_string_literal: true

module Badline
  module Frontend
    # Draws the SID's filter as the player shows it: its modes, cutoff,
    # resonance and volume, and its response across the audible range on
    # the chip playing, whose cutoff curve the two models don't share.
    class FilterView
      TEXT = SIDView::TEXT
      BRIGHT = SIDView::BRIGHT
      DIM = SIDView::DIM
      BOX = SIDView::BOX

      MODES = ["LP", "BP", "HP", "3 OFF"].freeze

      LEFT = SIDView::LEFT
      CURVE_LEFT = 224
      WIDTH = SIDView::WAVE_WIDTH
      HEIGHT = SIDView::PANEL_HEIGHT

      # The lowest and highest frequencies on the curve's axis.
      LOW_HZ = 30.0
      HIGH_HZ = 16_000.0

      def initialize(painter)
        @painter = painter
        @curve = Array.new(WIDTH + 1, 0)
      end

      def draw(history, frame, top, model)
        cutoff = (history.register(frame, 0x15) & 0x07) | (history.register(frame, 0x16) << 3)
        resonance = history.register(frame, 0x17) >> 4
        mode_volume = history.register(frame, 0x18)
        hertz = SID::Filter::W0.fetch(model)[cutoff] / (2 * Math::PI * SID::Filter::SCALE)
        paint = @painter
        paint.text(LEFT, top, "FILTER", BRIGHT)
        x = LEFT + 64
        MODES.each_with_index do |name, bit|
          x += paint.text(x, top, name, mode_volume[bit + 4] == 1 ? BRIGHT : DIM) + 8
        end
        paint.text(LEFT, top + 16, format("CUTOFF $%<cutoff>03X", cutoff:), TEXT)
        paint.text(LEFT, top + 28, format("  %<hertz>d HZ", hertz: hertz.round), TEXT)
        paint.text(LEFT, top + 40, format("RES %<res>X  VOL %<vol>X", res: resonance, vol: mode_volume & 0x0f), TEXT)
        draw_curve(hertz, resonance, mode_volume, top)
      end

      private

      # The gain for the modes selected on a logarithmic axis, with the
      # cutoff marked.
      def draw_curve(cutoff_hertz, resonance, mode_volume, top)
        paint = @painter
        paint.box(CURVE_LEFT, top, WIDTH, HEIGHT, BOX)
        return paint.text(CURVE_LEFT + 8, top + 8, "NO MODE", DIM) if mode_volume.nobits?(0x70)

        quality = 0.707 + (resonance / 15.0)
        cutoff = [cutoff_hertz, 1.0].max
        points = @curve
        x = 0
        while x <= WIDTH
          hertz = LOW_HZ * ((HIGH_HZ / LOW_HZ)**(x.to_f / WIDTH))
          decibels = gain(hertz / cutoff, quality, mode_volume).clamp(-36.0, 12.0)
          points[x] = Painter.point(CURVE_LEFT + x, top + 8 + (((12.0 - decibels) * (HEIGHT - 12)) / 48.0).round)
          x += 1
        end
        paint.polyline(points, BRIGHT)
        marker = (WIDTH * Math.log(cutoff / LOW_HZ) / Math.log(HIGH_HZ / LOW_HZ)).round
        paint.box(CURVE_LEFT + marker, top, 1, HEIGHT, DIM) if marker.between?(0, WIDTH)
      end

      # The gain in decibels of a two-pole state-variable filter at `ratio`
      # of its cutoff, summing the low-, band- and high-pass outputs chosen.
      def gain(ratio, quality, mode_volume)
        real = 1.0 - (ratio * ratio)
        imaginary = ratio / quality
        denominator = (real * real) + (imaginary * imaginary)
        out_real = 0.0
        out_imaginary = 0.0
        if mode_volume.anybits?(0x10)
          out_real += real / denominator
          out_imaginary -= imaginary / denominator
        end
        if mode_volume.anybits?(0x20)
          out_real += ratio * imaginary / denominator
          out_imaginary += ratio * real / denominator
        end
        if mode_volume.anybits?(0x40)
          out_real -= ratio * ratio * real / denominator
          out_imaginary += ratio * ratio * imaginary / denominator
        end
        magnitude = Math.sqrt((out_real * out_real) + (out_imaginary * out_imaginary))
        20.0 * Math.log([magnitude, 1.0e-6].max) / Math.log(10)
      end
    end
  end
end
