# frozen_string_literal: true

module Badline
  module Native
    class Options
      # What `badline --help` prints: badline-ruby's help, with the native
      # build's own options in the sections they belong to.
      HELP = <<~HELP.freeze
        Usage: badline [options] [media]
               badline --headless [options] tune.sid
               badline [options] tune.sid --audio-out FILE

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

        Without the window, PSID tunes run on a bare CPU and SID, and RSID
        tunes boot the whole machine. --filter-chunk 1 runs the filter
        cycle by cycle, which is exact but slower.

        Options:
            -s, --song N                     Subtune of a .sid, from 1 (default: the tune's own)
                --sid MODEL                  SID to fit: 6581 or 8580 (default: a .sid tune's own, else 6581)
            -h, --help                       Show this help
                --version                    Show the version and what built it

        Window options:
                --no-autostart               Boot to READY. instead of running the program
                --read-only                  Mount a disk image write-protected, leaving its file unchanged
                --sound                      Play the SID through the host's audio device (F10 mutes)#{' (default)' if SOUND}
                --no-sound                   Don't play the SID#{' (default)' unless SOUND}
                --true-drive                 Put a true 1541 on device 8 instead of the KERNAL traps
                --ntsc                       Run an NTSC C64, with the 6567R8 VIC-II, instead of a PAL one
                --no-vsync                   Pace frames by the timer or the sound instead of the display
                --verbose                    Print the display, sound and gamepad setup and the frame timing

        Options without the window:
                --headless                   Play a .sid tune in the terminal instead of the window
                --audio-out FILE             Render a .sid tune to a .wav or .aiff file
                --seconds N                  Length to play (default: the tune's own)
                --songlengths PATH           HVSC Songlengths.md5 to take the length from
                --rate HZ                    Sample rate (default: #{DEFAULT_RATE}, or the audio device's own)
                --filter-chunk N             Filter step in cycles, 1 is exact (default: 4)
                --quiet                      Don't report progress
                --no-tui                     Play without the interactive display, even on a terminal

        Testing options:
                --frames N                   Quit after N frames
                --unpaced                    Run as fast as it can, without vsync or pacing
                --screenshot FILE            Save the last frame as a .bmp
      HELP
    end
  end
end
