# frozen_string_literal: true

module Badline
  class Options
    DEFAULT_RATE = 44_100

    # The names Badline::Model builds, in the order the help lists them.
    MODELS = %w[c64 c64c ntsc newntsc oldntsc drean sx64 pet64 c64gs ultimax].freeze

    # The VIC-20's models, as xvic names its video standards.
    VIC20_MODELS = %w[pal ntsc].freeze

    # The C128's models, as C128::Model names them.
    C128_MODELS = %w[c128 c128ntsc c128dcr c128dcrntsc].freeze

    # The 264 series' models, as Plus4::Model names them, with the C116 as
    # another name for the C16.
    PLUS4_MODELS = %w[plus4 plus4ntsc c16 c16ntsc c116].freeze

    # The PETs and CBMs, as PET::Model names them, the 8032 first, the
    # default.
    PET_MODELS = %w[8032 8096 8296 4032 3032 3032b 2001 superpet].freeze

    # The CBM-II's B series, as CBM2::Model names them, the 610 first, the
    # default, and the P500, as CBM2::P500::Model names them.
    CBM2_MODELS = %w[610 620 710 720 510 510ntsc].freeze

    # The KIM-1, which has the one model.
    KIM1_MODELS = %w[kim1].freeze

    # The KIM-1 teletype's rates, as KIM1::Teletype takes them.
    KIM1_BAUDS = %w[110 300 1200 2400 4800 9600].freeze

    # The B series' KERNALs --kernal names, 901244-04a first, the default.
    CBM2_KERNALS = %w[04a 03b].freeze

    # The P500's one KERNAL, 901234-02.
    P500_KERNALS = %w[02].freeze

    # The true drives --drive-type names for the Plus/4.
    PLUS4_DRIVE_TYPES = %w[1541 1551].freeze

    # The VIC-20 RAM expansions --ram takes, in the order the help lists
    # them.
    RAM_NAMES = %w[unexpanded 3k 8k 16k 24k 32k all].freeze

    SECTIONS = ["Options", "Window options", "Options without the window", "Testing options"].freeze

    # Every option of both builds, in the order the help lists them.
    TABLE = [
      Option.new("-s, --subtune N", "Subtune of a .sid, from 1 (default: the tune's own)", section: "Options"),
      Option.new("--sid MODEL", "SID to fit: auto, 6581 or 8580 (default: auto, a .sid tune's own, else 6581)",
                 section: "Options"),
      Option.new("--disable-jit", "Run without enabling YJIT", section: "Options", build: :ruby),
      Option.new("-h, --help", "Show this help", section: "Options"),
      Option.new("--version", "Show the version and what built it", section: "Options", build: :native),
      Option.new("--tty", "Fit the KIM-1's TTY/KB jumper, so its monitor talks to a teletype: a pane in the " \
                          "window, or the terminal with --headless",
                 section: "Options"),
      Option.new("--baud N", "The KIM-1 teletype's baud: #{KIM1_BAUDS.join(', ')} (default: 9600)",
                 section: "Options"),
      Option.new("--no-autostart", "Boot to READY. instead of running the program",
                 section: "Window options", needs: :window),
      Option.new("--writable", "Let the machine write to disk images, changing their files",
                 section: "Window options", needs: :window),
      Option.new("--sound", "Play the SID through the host's audio device (F10 mutes)",
                 section: "Window options", needs: :window),
      Option.new("--no-sound", "Don't play the SID", section: "Window options", needs: :window, build: :native),
      Option.new("--true-drive", "Put a true 1541 on device 8 instead of the KERNAL traps, a 1571 on the C128, " \
                                 "a 1551 on the Plus/4, a 2031 on the PET or the CBM-II, or for a .d80 or .d82 " \
                                 "an 8050 or 8250",
                 section: "Window options", needs: :window),
      Option.new("--drive-type MODEL", "The Plus/4's true drive: 1541 or 1551 (default: 1551); the PET's and the " \
                                       "CBM-II's: #{Drives::IEEEModels::NAMES.join(', ')} (default: 2031); " \
                                       "implies --true-drive",
                 section: "Window options", needs: :window),
      Option.new("--reu SIZE", "Plug in an REU of SIZE K: 128, 256, 512 (a 1750) or up to 16384",
                 section: "Window options", needs: :window),
      Option.new("--model NAME", "C64 to run: #{MODELS.join(', ')} (default: #{MODELS.first}); " \
                                 "VIC-20: #{VIC20_MODELS.join(', ')}; C128: #{C128_MODELS.join(', ')}; " \
                                 "Plus/4: #{PLUS4_MODELS.join(', ')}; " \
                                 "PET: #{PET_MODELS.join(', ')}; CBM-II: #{CBM2_MODELS.join(', ')}",
                 section: "Window options", needs: :window),
      Option.new("--ntsc", "Run an NTSC C64 or VIC-20, as --model ntsc does",
                 section: "Window options", needs: :window),
      Option.new("--c64", "Start the C128 in C64 mode, holding C= at power-on",
                 section: "Window options", needs: :window),
      Option.new("--ram SIZE", "VIC-20 RAM expansion: #{RAM_NAMES.join(', ')} (default: unexpanded); " \
                               "Plus/4 RAM: 16k, 32k or 64k; PET RAM: 4k, 8k, 16k or 32k (default: the model's own)",
                 section: "Window options", needs: :window),
      Option.new("--60hz", "Run a CRTC PET's 60 Hz editor instead of its 50 Hz one, or a CBM-II on 60 Hz mains",
                 section: "Window options", needs: :window),
      Option.new("--kernal VERSION", "Fit a CBM-II with KERNAL #{CBM2_KERNALS.join(' or ')} " \
                                     "(default: #{CBM2_KERNALS.first}); the P500 takes #{P500_KERNALS.first}",
                 section: "Window options", needs: :window),
      Option.new("--basic VERSION", "Fit a PET with BASIC 1, 2 or 4, as its board takes (default: its own)",
                 section: "Window options", needs: :window),
      Option.new("--editor NAME", "Fit a PET with an editor ROM its board and BASIC take: " \
                                  "#{PET::ROMSets::EDITORS.keys.join(', ')}",
                 section: "Window options", needs: :window),
      Option.new("--characters NAME", "Fit an 8296 with a character ROM: ascii or din (default: ascii)",
                 section: "Window options", needs: :window),
      Option.new("--jumpers LIST", "Fit an 8296's board with jumpers, comma-separated: ram9 and rama for RAM at " \
                                   "$9000 and $A000, userport for the user port's PA0-PA2 to switch in " \
                                   "the RAM under the ROMs",
                 section: "Window options", needs: :window),
      Option.new("--cpu CPU", "Set the SuperPET's CPU switch: 6502, 6809 or prog, for the system latch to pick " \
                              "(default: 6502)",
                 section: "Window options", needs: :window),
      Option.new("--bank-ram MODE", "Set the SuperPET's bank RAM switch: rw, read for write-protected, or prog, " \
                                    "for the system latch to pick (default: rw)",
                 section: "Window options", needs: :window),
      Option.new("--c1lo FILE", "Put a .bin ROM image in the Plus/4's cartridge 1, low slot ($8000)",
                 section: "Window options", needs: :window),
      Option.new("--c1hi FILE", "Put a .bin ROM image in cartridge 1's high slot ($C000)",
                 section: "Window options", needs: :window),
      Option.new("--c2lo FILE", "Put a .bin ROM image in cartridge 2's low slot ($8000)",
                 section: "Window options", needs: :window),
      Option.new("--c2hi FILE", "Put a .bin ROM image in cartridge 2's high slot ($C000)",
                 section: "Window options", needs: :window),
      Option.new("--sid-card MODEL", "Fit the Plus/4 or C16 with a SID card at $FD40: 6581 or 8580",
                 section: "Window options", needs: :window),
      Option.new("--sid-card-address ADDRESS", "Put the SID card at fd40 (the default) or fe80",
                 section: "Window options", needs: :window),
      Option.new("--ram-expansion NAME", "Fit the Plus/4 or C16 with a RAM expansion: hannes256, hannes1m or csory256",
                 section: "Window options", needs: :window),
      Option.new("--no-vsync", "Pace frames by the timer or the sound instead of the display",
                 section: "Window options", needs: :window),
      Option.new("--verbose", "Print the display, sound and gamepad setup and the frame timing",
                 section: "Window options", needs: :window),
      Option.new("--headless", "Play a .sid tune, or run the KIM-1's teletype, in the terminal instead of the window",
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
      Option.new("--all-subtunes", "Play on through each tune's subtunes, not just the one",
                 section: "Options without the window", needs: :headless),
      Option.new("--no-tui", "Play without the interactive display, even on a terminal",
                 section: "Options without the window", needs: :headless),
      Option.new("--frames N", "Quit after N frames", section: "Testing options", needs: :any_window),
      Option.new("--unpaced", "Run as fast as it can, without vsync or pacing",
                 section: "Testing options", needs: :window),
      Option.new("--screenshot FILE", "Save the last frame as a .bmp",
                 section: "Testing options", needs: :window),
      Option.new("--save-snapshot FILE", "Save the machine as a .vsf snapshot after the last frame",
                 section: "Testing options", needs: :window),
      Option.new("--vice", "Add VICE's modules to --save-snapshot's C64, PET or CBM-II snapshot",
                 section: "Testing options", needs: :window),
      Option.new("--at FRAME:EVENT", "Run EVENT once FRAME frames have run (see above)",
                 section: "Testing options", needs: :window),
      Option.new("--script FILE", "Run the events in FILE, one FRAME:EVENT a line",
                 section: "Testing options", needs: :window)
    ].freeze
  end
end
