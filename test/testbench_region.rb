# frozen_string_literal: true

# The video standard of a bin/testbench row, for --ntsc.
module Testbench
  NTSC_OPTION = "vicii-ntsc"
  NTSC_OLD_OPTION = "vicii-ntscold"

  # A TestCase's video standard and the reference screenshot it compares
  # against.
  module RegionRow
    # The video standard the row asks for: :ntsc for the 6567R8 of
    # vicii-ntsc, :ntscold for the 6567R56A of vicii-ntscold, else :pal.
    def region
      if options.include?(NTSC_OLD_OPTION) then :ntscold
      elsif options.include?(NTSC_OPTION) then :ntsc
      else :pal
      end
    end

    def ntsc? = region != :pal

    # An 8565 row compares against the program's 8565 reference, or on NTSC
    # its 8562 one, and an NTSC row against its -ntsc or -ntscold one, as
    # VICE's testbench does. Each falls back to the generic reference where
    # there is none.
    def reference
      base = File.join(dir_abs, "references", prg.empty? ? cartridge : prg)
      candidates = []
      candidates << "#{base}-#{ntsc? ? 8562 : 8565}.png" if vic_model == :mos8565
      candidates << "#{base}-#{region}.png" if ntsc?
      candidates.find { |path| File.exist?(path) } || "#{base}.png"
    end
  end
end
