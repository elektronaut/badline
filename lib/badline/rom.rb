# frozen_string_literal: true

module Badline
  class ROM < Memory
    class << self
      def load(filename, start = 0x0)
        data = File.read(file_path(filename)).bytes
        new(data, length: data.length, start: start)
      end

      private

      def file_path(filename)
        File.join(rom_dir, filename)
      end

      # Ahead-of-time compiled, there is no source tree beside the binary and
      # __FILE__ names the entry script, so allow the ROM directory to be
      # pointed at explicitly.
      def rom_dir
        from_env = ENV.fetch("BADLINE_ROMS", nil)
        return from_env unless from_env.nil? || from_env.empty?

        File.join(File.dirname(__FILE__), "roms")
      end
    end

    def poke(_addr, _value)
      raise ReadOnlyMemoryError
    end
    alias []= poke
  end
end
