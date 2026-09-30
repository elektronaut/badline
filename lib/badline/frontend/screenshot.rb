# frozen_string_literal: true

module Badline
  module Frontend
    # --screenshot's frame: what the renderer drew, read back before it is
    # presented and saved as a BMP.
    module Screenshot
      def self.write(renderer, path)
        SDL.SDL_GetRendererOutputSize(renderer, SDL.output_w, SDL.output_h)
        width = SDL.read_i32(SDL.output_w)
        height = SDL.read_i32(SDL.output_h)
        data = LibC.malloc(width * height * 4)
        SDL.SDL_RenderReadPixels(renderer, nil, SDL::PIXELFORMAT_RGB888, data, width * 4)
        surface = SDL.SDL_CreateRGBSurfaceWithFormatFrom(data, width, height, 32, width * 4, SDL::PIXELFORMAT_RGB888)
        SDL.SDL_SaveBMP_RW(surface, SDL.SDL_RWFromFile(path, "wb"), 1)
        SDL.SDL_FreeSurface(surface)
        LibC.free(data)
        puts "wrote #{path}, #{width}x#{height}"
      end
    end
  end
end
