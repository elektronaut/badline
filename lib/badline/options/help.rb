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
      lines = [@sid_command ? sid_banner : banner]
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
               #{@program} sid [options] FILE|DIR...

        Media can be a .prg/.p00 program, a .d64/.d71/.d81 disk image, a
        .g64 disk image for the true 1541, a .t64 tape archive, a .tap
        tape, a .crt cartridge, a .sid tune, a .vsf snapshot, or a directory
        to mount as device 8. It opens in the emulator window, where F11
        saves a snapshot and F12 restores it. Device 8 answers through
        traps on the KERNAL's disk routines, unless --true-drive puts an
        emulated 1541 there, which runs its own DOS and reads .d64 and .g64
        images only.

        --headless plays a .sid tune on the host's audio device without the
        window, and --audio-out renders it to 16-bit PCM instead. The
        container follows the file's extension, .wav or .aiff. Played on a
        terminal, → and ← step between the tune's subtunes, n and p between
        tunes, , and . seek, space pauses and q quits. s shuffles the tunes,
        l loops them, and a, or --all-subtunes, plays on through each tune's
        subtunes instead of just the one. `#{@program} sid` plays many tunes, and whole
        directories of them, the same way.

        A .sid file carries no length of its own. Without --seconds the tune is
        looked up by MD5 in HVSC's Songlengths.md5, taken from --songlengths, from
        the DOCUMENTS directory of an HVSC collection above the tune, or from
        $HVSC_BASE. Failing all of those it runs for #{FALLBACK_SECONDS.to_i} seconds, or
        until it has been silent for #{SILENCE_SECONDS.to_i}.

        #{@native ? NATIVE_SPEED : RUBY_SPEED}

        --at and --script run events once a number of frames has run, as
        in --at 3500:key=space or --at 250,500:screenshot=shot%05d.bmp.
        key=NAME presses a C64 key (space, return, a, f1, run_stop, restore)
        or a joystick's direction or fire (joy1-up, joy2-fire) for #{Event::HOLD}
        frames. type=TEXT types it, with \\n for RETURN. insert=FILE swaps
        in a disk, tape or cartridge, and eject=disk, tape or cartridge
        takes one out. screenshot=FILE saves the frame as a .bmp, with the
        frame's number in place of %d. reset, freeze and quit take no
        argument.
      BANNER
    end

    def sid_banner
      <<~BANNER
        Usage: #{@program} sid [options] FILE|DIR...

        Plays .sid tunes in the SID player's window, or in the terminal with
        --headless, one after another in the order given. A directory adds
        every .sid tune below it, in path order. → and ← step between a
        tune's subtunes, n and p between tunes, , and . seek 10 seconds back
        and forward, space pauses and q quits. s shuffles the tunes, l loops
        them, and a, or --all-subtunes, plays on through each tune's subtunes
        instead of just the one. The window has buttons for all of these,
        and for switching the SID between the tune's own, the 6581 and the
        8580.
        --subtune picks the first tune's subtune, and each tune after it starts on
        its own.

        Each tune gets the SID its header names unless --sid says otherwise,
        and its length from HVSC's Songlengths.md5 as #{@program} --help
        describes. A tune written for 2 or 3 SIDs plays on the one badline
        emulates, with a notice.
      BANNER
    end
  end
end
