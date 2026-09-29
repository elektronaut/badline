# frozen_string_literal: true

module Badline
  class Options
    # How fast the headless player runs, which the builds' help tells apart.
    NATIVE_SPEED = <<~TEXT.chomp
      Without the window, PSID tunes run on a bare CPU and SID, and RSID
      tunes boot the whole machine. --filter-chunk 1 runs the filter
      cycle by cycle, which is exact but slower.
    TEXT

    RUBY_SPEED = <<~TEXT.chomp
      Without the window, PSID tunes run on a bare CPU and SID, faster than
      real time. RSID tunes boot the whole machine and run at about half
      real time, so they stutter when played. --filter-chunk 1 runs the
      filter cycle by cycle, which is exact but takes about twice as long.
    TEXT

    # What --help prints: the usage, then the options this build takes,
    # section by section, laid out as OptionParser did.
    def help
      lines = [banner]
      SECTIONS.each do |section|
        options = TABLE.select { |option| option.section == section && takes?(option) }
        next if options.empty?

        lines << "" if lines.size > 1
        lines << "#{section}:"
        options.each { |option| lines << "    #{option.usage.ljust(32)} #{describe(option)}" }
      end
      "#{lines.join("\n")}\n"
    end

    private

    def describe(option) = @native && option.name == "--sound" ? "#{option.text} (default)" : option.text

    def banner
      <<~BANNER
        Usage: #{@program} [options] [media]
               #{@program} --headless [options] tune.sid
               #{@program} [options] tune.sid --audio-out FILE

        Media can be a .prg/.p00 program, a .d64/.d71/.d81 disk image, a
        .g64 disk image for the true 1541, a .t64 tape archive, a .tap
        tape, a .crt cartridge, a .sid tune, or a directory to mount as
        device 8. It opens in the emulator window. Device 8 answers through
        traps on the KERNAL's disk routines, unless --true-drive puts an
        emulated 1541 there, which runs its own DOS and reads .d64 and .g64
        images only.

        --headless plays a .sid tune on the host's audio device without the
        window, and --audio-out renders it to 16-bit PCM instead. The
        container follows the file's extension, .wav or .aiff. Played on a
        terminal, n or → skips to the next song, p or ← to the previous one,
        space pauses and q quits.

        A .sid file carries no length of its own. Without --seconds the tune is
        looked up by MD5 in HVSC's Songlengths.md5, taken from --songlengths, from
        the DOCUMENTS directory of an HVSC collection above the tune, or from
        $HVSC_BASE. Failing all of those it runs for #{FALLBACK_SECONDS.to_i} seconds.

        #{@native ? NATIVE_SPEED : RUBY_SPEED}
      BANNER
    end
  end
end
