# frozen_string_literal: true

module Badline
  class Options
    DEFAULT_RATE = 44_100

    SECTIONS = ["Options", "Window options", "Options without the window", "Testing options"].freeze

    # Every option of both builds, in the order the help lists them.
    TABLE = [
      Option.new("-s, --song N", "Subtune of a .sid, from 1 (default: the tune's own)", section: "Options"),
      Option.new("--sid MODEL", "SID to fit: 6581 or 8580 (default: a .sid tune's own, else 6581)",
                 section: "Options"),
      Option.new("--disable-jit", "Run without enabling YJIT", section: "Options", build: :ruby),
      Option.new("-h, --help", "Show this help", section: "Options"),
      Option.new("--version", "Show the version and what built it", section: "Options", build: :native),
      Option.new("--no-autostart", "Boot to READY. instead of running the program",
                 section: "Window options", needs: :window),
      Option.new("--read-only", "Mount a disk image write-protected, leaving its file unchanged",
                 section: "Window options", needs: :window),
      Option.new("--sound", "Play the SID through the host's audio device (F10 mutes)",
                 section: "Window options", needs: :window),
      Option.new("--no-sound", "Don't play the SID", section: "Window options", needs: :window, build: :native),
      Option.new("--true-drive", "Put a true 1541 on device 8 instead of the KERNAL traps",
                 section: "Window options", needs: :window),
      Option.new("--reu SIZE", "Plug in an REU of SIZE K: 128, 256, 512 (a 1750) or up to 16384",
                 section: "Window options", needs: :window),
      Option.new("--ntsc", "Run an NTSC C64, with the 6567R8 VIC-II, instead of a PAL one",
                 section: "Window options", needs: :window),
      Option.new("--no-vsync", "Pace frames by the timer or the sound instead of the display",
                 section: "Window options", needs: :window, build: :native),
      Option.new("--verbose", "Print the display, sound and gamepad setup and the frame timing",
                 section: "Window options", needs: :window),
      Option.new("--headless", "Play a .sid tune in the terminal instead of the window",
                 section: "Options without the window"),
      Option.new("--audio-out FILE", "Render a .sid tune to a .wav or .aiff file",
                 section: "Options without the window"),
      Option.new("--seconds N", "Length to play (default: the tune's own)",
                 section: "Options without the window", needs: :headless),
      Option.new("--songlengths PATH", "HVSC Songlengths.md5 to take the length from",
                 section: "Options without the window", needs: :headless),
      Option.new("--rate HZ", "Sample rate (default: #{DEFAULT_RATE}, or the audio device's own)",
                 section: "Options without the window", needs: :headless),
      Option.new("--filter-chunk N", "Filter step in cycles, 1 is exact (default: 4)",
                 section: "Options without the window", needs: :headless),
      Option.new("--quiet", "Don't report progress", section: "Options without the window", needs: :headless),
      Option.new("--no-tui", "Play without the interactive display, even on a terminal",
                 section: "Options without the window", needs: :headless),
      Option.new("--frames N", "Quit after N frames", section: "Testing options", needs: :window, build: :native),
      Option.new("--unpaced", "Run as fast as it can, without vsync or pacing",
                 section: "Testing options", needs: :window, build: :native),
      Option.new("--screenshot FILE", "Save the last frame as a .bmp",
                 section: "Testing options", needs: :window, build: :native),
      Option.new("--save-snapshot FILE", "Save the machine as a .vsf snapshot after the last frame",
                 section: "Testing options", needs: :window, build: :native)
    ].freeze
  end
end
