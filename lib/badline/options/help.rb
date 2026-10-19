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

    # The article for +name+: "an" where it starts with a vowel sound. A
    # name of letters with a vowel among them is read as a word, and any
    # other letter by letter, so .sid and .tap take "a", and .m3u and .lnx
    # "an".
    def self.article(name)
      word = name.delete_prefix(".").downcase
      vowels = word.match?(/\A[a-z]*[aeiou][a-z]*\z/) ? "aeiou" : "aefhilmnorsx8"
      vowels.include?(word[0]) ? "an" : "a"
    end

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

    # The media the window opens, by their extensions (Media::Extensions),
    # wrapped as the banner is.
    def media_kinds
      text = "Media can be #{listed(Media::Extensions::PROGRAMS)} program, #{listed(%i[disk])} disk image, " \
             "#{listed(%i[ieee_disk])} disk image or #{listed(%i[hard_disk])} hard disk for a PET, " \
             "#{listed(%i[gcr])} disk image for a true drive, #{listed(%i[disk_list])} list of disk images, " \
             "#{listed(%i[archive])} tape archive, #{listed(%i[tape])} tape, #{listed(%i[cartridge])} " \
             "cartridge, #{listed(%i[tune])} tune, #{listed(%w[.vsf])} snapshot, or a directory to mount as device 8."
      wrap(text)
    end

    # The extensions of the kinds, or the extensions themselves, after the
    # article the first takes.
    def listed(kinds)
      extensions = kinds.first.is_a?(Symbol) ? Media::Extensions.of(kinds) : kinds
      "#{Options.article(extensions.first)} #{extensions.join('/')}"
    end

    # The words of `text` in lines of at most 70 characters.
    def wrap(text)
      lines = [""]
      text.split.each do |word|
        line = lines.last
        if line.empty?
          lines[-1] = word
        elsif line.size + word.size < 70
          lines[-1] = "#{line} #{word}"
        else
          lines << word
        end
      end
      lines.join("\n")
    end

    def banner
      <<~BANNER
        Usage: #{@program} [c64] [options] [media]
               #{@program} vic20 [options] [media]
               #{@program} c128 [options] [media]
               #{@program} plus4 [options] [media]
               #{@program} pet [options] [media]
               #{@program} cbm2 [options] [media]
               #{@program} --headless [options] tune.sid
               #{@program} [options] tune.sid --audio-out FILE
               #{@program} sid [options] FILE|DIR...

        Commands:
            c64                              Run a C64, the one --model names (the default)
            vic20                            Run a VIC-20, PAL or --ntsc, with the RAM --ram names
            c128                             Run a C128 in C128 mode, the one --model names
            plus4                            Run a Plus/4 or a C16, the one --model names
            pet                              Run a PET or a CBM, the one --model names
            cbm2                             Run a CBM-II, a B series or a P500, the one --model names
            sid                              Play .sid tunes and directories of them

        #{media_kinds}
        It opens in the emulator window. There F11 quicksaves the machine to
        the next of five slots in badline's data folder, replacing the
        oldest, and F12 restores the newest quicksave or named save. The
        window also autosaves every two minutes of play, which only the
        pause menu loads. Device 8 answers through traps on the KERNAL's
        disk routines, unless --true-drive puts an emulated 1541 there,
        which runs its own DOS and reads .d64 and .g64 images only, or on
        the C128 the C128D's 1571, which reads .d71 and .g71 too. A .d81
        then goes in an emulated 1581 in its place. A .sid
        tune opens in the SID player, as `sid` plays it, unless an option
        of the emulator's window asks for the machine.

        The Plus/4 and the C16 take programs, disks, tapes, and cartridges as
        .crt files or raw .bin ROM images. A .bin goes in cartridge 1, its
        low slot for up to 16K and both slots for 32K, and --c1lo, --c1hi,
        --c2lo and --c2hi put one in the slot they name. Their --true-drive
        makes device 8 an emulated 1551, on the parallel TCBM cable, and
        --drive-type 1541 a 1541 on the serial bus instead. There Escape is
        ESC, Page Down RUN/STOP and F4 HELP.

        The PET and the CBM take programs, disks, .d80 and .d82 among them,
        and tapes, and a .d80, a .d82 or a PET tape starts one without
        `pet`. Their keys type what the host's keys type, Alt with a key
        presses the PET's SHIFT and the key its unshifted character is on,
        and the pause menu's KEYBOARD page says where the rest are. --basic
        and --editor fit the upgrades Commodore sold, as in --model 2001
        --basic 2. BASIC 1 can't LOAD from a disk drive, though a disk still
        starts its first program, and BASIC 2 can. Their --true-drive makes
        device 8 an emulated 2031 on the IEEE-488 bus, which reads .d64 and
        .g64 images, and a .d80 or a .d82 then goes in an emulated 8050 or
        8250. --drive-type 8050 or 8250 plugs either in instead, and
        --drive-type 1001 an SFD-1001, which takes a .d82 in its one drive.
        The 8032 and the 8096 have two 50 Hz editors: 4-80-b-50hz, the
        default, and 4-80-b-50hz-0283, another chip's,
        with 64-cycle lines and 313 lines a frame. The 8296 runs its own,
        4-80-b-50hz-8296, and takes the 8032's too. --characters din fits
        it with the DIN character ROM, and --jumpers ram9,rama puts RAM at
        $9000 and $A000, as xpet's -petram9 and -petramA do.

        The CBM-II takes programs, disks, .d80 and .d82 among them, and
        cartridges, and a cartridge made for it starts one without `cbm2`.
        --kernal 03b fits the 1983 KERNAL in place of 04a, and --60hz runs
        it on 60 Hz mains. Its --true-drive makes device 8 an emulated 2031
        on its IEEE-488 bus, which reads .d64 and .g64 images, and a .d80
        or a .d82 then goes in an emulated 8050 or 8250, and --drive-type
        plugs in either from the start, as on the PET. Its keys type what
        the host's keys type, F12 is RUN/STOP, Alt with F9 or F10 presses
        its F9 or F10, and the pause menu's KEYBOARD page says where the
        rest are. --model 510 or 510ntsc runs the P500, on the VIC-II with
        KERNAL 02, whose keys are the B series' and whose two joysticks Tab
        switches to.

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
        key=NAME presses a key (space, return, a, f1, run_stop, restore, and
        on the C128 esc, help, keypad1 and the rest, on the Plus/4
        esc, help and f1 to f3, on the PET rvs, escape and kp1, and on
        the CBM-II escape, norm_graph and kp00) or a joystick's
        direction or fire (joy1-up, joy2-fire) for #{Event::HOLD} frames, and
        pushes the C128's caps_lock or forty_eighty, which lock. type=TEXT
        types it, with \\n for RETURN. insert=FILE swaps in a disk, a list's
        first disk, a tape or a cartridge, and eject=disk, tape or
        cartridge takes one out. screenshot=FILE saves the frame as a .bmp,
        with the frame's number in place of %d. menu opens the pause menu,
        and menu=PAGE opens it on snapshots, drive, datasette, expansion,
        ports, sound or power. Its frames still count, and resume closes
        it. display=vdc or display=vic shows the C128's 80 or 40 column
        screen, as F8 switches them. reset, freeze and quit take no argument.
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
        8580. --subtune picks the first tune's subtune, and each tune after
        it starts on its own. Without tunes, the window opens with an empty
        queue, and .sid files or folders dropped on the window join it.

        Each tune gets the SID its header names unless --sid says otherwise,
        and its length from HVSC's Songlengths.md5 as #{@program} --help
        describes. A tune written for 2 or 3 SIDs plays on the one badline
        emulates, with a notice.
      BANNER
    end
  end
end
