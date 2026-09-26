# frozen_string_literal: true

module Badline
  module GUI
    class Pane
      attr_reader :left, :top, :width, :height

      def initialize(width:, height:, left: 0, top: 0)
        @width = width
        @height = height
        @left = left
        @top = top
        @rect = [left, top, width, height].pack("l4")
      end

      def render(_renderer)
        raise NotImplementedError, "#{self.class} must implement #render"
      end

      private

      # The pixels are little-endian RGBA dwords, red in the low byte.
      def blit(renderer, pixels)
        surface = SDL::CreateRGBSurfaceFrom.call(
          pixels, width, height, 32, width * 4,
          0x0000_00ff, 0x0000_ff00, 0x00ff_0000, 0xff00_0000
        )
        texture = SDL::CreateTextureFromSurface.call(renderer, surface)
        SDL::RenderCopy.call(renderer, texture, nil, @rect)
      ensure
        SDL::DestroyTexture.call(texture) if texture
        SDL::FreeSurface.call(surface) if surface
      end
    end
  end
end
