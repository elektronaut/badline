# frozen_string_literal: true

module Badline
  class << self
    attr_writer :rom_path

    # The directory ROM images and other bundled binaries load from.
    # Defaults to $BADLINE_ROM_PATH, then to the roms directory next to this
    # file. Assigning nil restores the default.
    def rom_path
      @rom_path ||= ENV.fetch("BADLINE_ROM_PATH", File.expand_path("roms", __dir__))
    end
  end

  class ROM < Memory
    class << self
      def load(filename, start = 0x0)
        data = read(filename)
        new(data, length: data.length, start: start)
      end

      def read(filename)
        File.binread(File.join(Badline.rom_path, filename)).bytes
      end
    end

    def poke(_addr, _value)
      raise ReadOnlyMemoryError
    end
    alias []= poke
  end
end
