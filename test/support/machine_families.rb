# frozen_string_literal: true

require_relative "../../lib/badline/support/plus4_checkpoint"
require_relative "../../lib/badline/support/pet_checkpoint"
require_relative "../../lib/badline/support/cbm2_checkpoint"
require_relative "../../lib/badline/support/p500_checkpoint"
require_relative "../../lib/badline/support/kim1_checkpoint"
require_relative "true_drive"

# 10 SYS2061, then the demo at $080D. The IRQ handler sits at $0885.
DEMO_PRG = [
  0x01, 0x08, # load address
  0x0b, 0x08, 0x0a, 0x00, 0x9e, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00,
  0x78,                   # sei
  0xa9, 0x7f,             # lda #$7f
  0x8d, 0x0d, 0xdc,       # sta $dc0d
  0xad, 0x0d, 0xdc,       # lda $dc0d
  0xa9, 0x01,             # lda #$01
  0x8d, 0x1a, 0xd0,       # sta $d01a
  0xa9, 0x1b,             # lda #$1b
  0x8d, 0x11, 0xd0,       # sta $d011
  0xa9, 0x80,             # lda #$80
  0x8d, 0x12, 0xd0,       # sta $d012
  0xa9, 0x85,             # lda #<irq
  0x8d, 0x14, 0x03,       # sta $0314
  0xa9, 0x08,             # lda #>irq
  0x8d, 0x15, 0x03,       # sta $0315
  0xa2, 0x3f,             # ldx #$3f
  0x8a,                   # txa
  0x9d, 0x40, 0x03,       # sta $0340,x
  0xca,                   # dex
  0x10, 0xf9,             # bpl $0831
  0xa2, 0x0f,             # ldx #$0f
  0x8a,                   # txa
  0x0a, 0x0a, 0x0a, 0x0a, # asl x4
  0x69, 0x30,             # adc #$30
  0x9d, 0x00, 0xd0,       # sta $d000,x
  0xca,                   # dex
  0x10, 0xf3,             # bpl $083a
  0xa2, 0x07,             # ldx #$07
  0xa9, 0x0d,             # lda #$0d
  0x9d, 0xf8, 0x07,       # sta $07f8,x
  0x8a,                   # txa
  0x9d, 0x27, 0xd0,       # sta $d027,x
  0xca,                   # dex
  0x10, 0xf4,             # bpl $0849
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x15, 0xd0,       # sta $d015
  0x8d, 0x1c, 0xd0,       # sta $d01c
  0xa9, 0x0f,             # lda #$0f
  0x8d, 0x18, 0xd4,       # sta $d418
  0xa9, 0x10,             # lda #$10
  0x8d, 0x01, 0xd4,       # sta $d401
  0xa9, 0x09,             # lda #$09
  0x8d, 0x05, 0xd4,       # sta $d405
  0xa9, 0x21,             # lda #$21
  0x8d, 0x04, 0xd4,       # sta $d404
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x04, 0xdd,       # sta $dd04
  0x8d, 0x05, 0xdd,       # sta $dd05
  0xa9, 0x11,             # lda #$11
  0x8d, 0x0e, 0xdd,       # sta $dd0e
  0x58,                   # cli
  0xee, 0x00, 0x04,       # inc $0400
  0x4c, 0x7f, 0x08,       # jmp $087f
  0xee, 0x19, 0xd0,       # irq: inc $d019
  0xee, 0x21, 0xd0,       # inc $d021
  0xe6, 0xfb,             # inc $fb
  0xa5, 0xfb,             # lda $fb
  0x8d, 0x01, 0xd4,       # sta $d401
  0xad, 0x12, 0xd0,       # lda $d012
  0x49, 0x40,             # eor #$40
  0x8d, 0x12, 0xd0,       # sta $d012
  0x4c, 0x81, 0xea        # jmp $ea81
].pack("C*").freeze

# The C128 mode demo: 10 SYS7181, then DEMO_PRG's program at $1C0D, with
# the sprites at $0E00, the IRQ handler at $1C85 and the KERNAL's IRQ exit
# at $FF33. The handler also writes VDC register 26 and the MMU's PCRB.
C128_DEMO_PRG = [
  0x01, 0x1c, # load address
  0x0b, 0x1c, 0x0a, 0x00, 0x9e, 0x37, 0x31, 0x38, 0x31, 0x00, 0x00, 0x00,
  0x78,                   # sei
  0xa9, 0x7f,             # lda #$7f
  0x8d, 0x0d, 0xdc,       # sta $dc0d
  0xad, 0x0d, 0xdc,       # lda $dc0d
  0xa9, 0x01,             # lda #$01
  0x8d, 0x1a, 0xd0,       # sta $d01a
  0xa9, 0x1b,             # lda #$1b
  0x8d, 0x11, 0xd0,       # sta $d011
  0xa9, 0x80,             # lda #$80
  0x8d, 0x12, 0xd0,       # sta $d012
  0xa9, 0x85,             # lda #<irq
  0x8d, 0x14, 0x03,       # sta $0314
  0xa9, 0x1c,             # lda #>irq
  0x8d, 0x15, 0x03,       # sta $0315
  0xa2, 0x3f,             # ldx #$3f
  0x8a,                   # txa
  0x9d, 0x00, 0x0e,       # sta $0e00,x
  0xca,                   # dex
  0x10, 0xf9,             # bpl $1c31
  0xa2, 0x0f,             # ldx #$0f
  0x8a,                   # txa
  0x0a, 0x0a, 0x0a, 0x0a, # asl x4
  0x69, 0x30,             # adc #$30
  0x9d, 0x00, 0xd0,       # sta $d000,x
  0xca,                   # dex
  0x10, 0xf3,             # bpl $1c3a
  0xa2, 0x07,             # ldx #$07
  0xa9, 0x38,             # lda #$38
  0x9d, 0xf8, 0x07,       # sta $07f8,x
  0x8a,                   # txa
  0x9d, 0x27, 0xd0,       # sta $d027,x
  0xca,                   # dex
  0x10, 0xf4,             # bpl $1c49
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x15, 0xd0,       # sta $d015
  0x8d, 0x1c, 0xd0,       # sta $d01c
  0xa9, 0x0f,             # lda #$0f
  0x8d, 0x18, 0xd4,       # sta $d418
  0xa9, 0x10,             # lda #$10
  0x8d, 0x01, 0xd4,       # sta $d401
  0xa9, 0x09,             # lda #$09
  0x8d, 0x05, 0xd4,       # sta $d405
  0xa9, 0x21,             # lda #$21
  0x8d, 0x04, 0xd4,       # sta $d404
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x04, 0xdd,       # sta $dd04
  0x8d, 0x05, 0xdd,       # sta $dd05
  0xa9, 0x11,             # lda #$11
  0x8d, 0x0e, 0xdd,       # sta $dd0e
  0x58,                   # cli
  0xee, 0x00, 0x04,       # inc $0400
  0x4c, 0x7f, 0x1c,       # jmp $1c7f
  0xee, 0x19, 0xd0,       # irq: inc $d019
  0xee, 0x21, 0xd0,       # inc $d021
  0xe6, 0xfb,             # inc $fb
  0xa5, 0xfb,             # lda $fb
  0x8d, 0x01, 0xd4,       # sta $d401
  0xad, 0x12, 0xd0,       # lda $d012
  0x49, 0x40,             # eor #$40
  0x8d, 0x12, 0xd0,       # sta $d012
  0xa2, 0x1a,             # ldx #$1a
  0x8e, 0x00, 0xd6,       # stx $d600
  0x2c, 0x00, 0xd6,       # bit $d600
  0x10, 0xfb,             # bpl $1c9f
  0xa5, 0xfb,             # lda $fb
  0x8d, 0x01, 0xd6,       # sta $d601
  0x8d, 0x02, 0xd5,       # sta $d502
  0x4c, 0x33, 0xff        # jmp $ff33
].pack("C*").freeze

# The VIC-20 demo: 10 SYS4109, then the demo at $100D, for an unexpanded
# VIC-20. The IRQ handler sits at $103B and goes on to the KERNAL's at
# $EABF.
VIC20_DEMO_PRG = [
  0x01, 0x10, # load address
  0x0b, 0x10, 0x0a, 0x00, 0x9e, 0x34, 0x31, 0x30, 0x39, 0x00, 0x00, 0x00,
  0x78,                   # sei
  0xa9, 0x3b,             # lda #<irq
  0x8d, 0x14, 0x03,       # sta $0314
  0xa9, 0x10,             # lda #>irq
  0x8d, 0x15, 0x03,       # sta $0315
  0xa9, 0x0f,             # lda #$0f
  0x8d, 0x0e, 0x90,       # sta $900e
  0xa9, 0xc0,             # lda #$c0
  0x8d, 0x0b, 0x90,       # sta $900b
  0xa9, 0xf0,             # lda #$f0
  0x8d, 0x0d, 0x90,       # sta $900d
  0xa9, 0x40,             # lda #$40
  0x8d, 0x1b, 0x91,       # sta $911b
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x14, 0x91,       # sta $9114
  0x8d, 0x15, 0x91,       # sta $9115
  0x58,                   # cli
  0xee, 0x00, 0x1e,       # inc $1e00
  0x4c, 0x35, 0x10,       # jmp $1035
  0xee, 0x0f, 0x90,       # irq: inc $900f
  0xe6, 0xfb,             # inc $fb
  0xa5, 0xfb,             # lda $fb
  0x09, 0x80,             # ora #$80
  0x8d, 0x0c, 0x90,       # sta $900c
  0x4c, 0xbf, 0xea        # jmp $eabf
].pack("C*").freeze

# The Plus/4 demo: 10 SYS4109, then the demo at $100D, which runs on the
# C16's 16K too. It starts TED timer 1 and voice 1, and hooks the KERNAL's
# IRQ at $1038 to step the border colour and the voice's pitch before going
# on to the KERNAL's handler, whose address it saves in its own JMP.
PLUS4_DEMO_PRG = [
  0x01, 0x10, # load address
  0x0b, 0x10, 0x0a, 0x00, 0x9e, 0x34, 0x31, 0x30, 0x39, 0x00, 0x00, 0x00,
  0x78,                   # sei
  0xad, 0x14, 0x03,       # lda $0314
  0x8d, 0x45, 0x10,       # sta $1045
  0xad, 0x15, 0x03,       # lda $0315
  0x8d, 0x46, 0x10,       # sta $1046
  0xa9, 0x38,             # lda #<irq
  0x8d, 0x14, 0x03,       # sta $0314
  0xa9, 0x10,             # lda #>irq
  0x8d, 0x15, 0x03,       # sta $0315
  0xa9, 0x18,             # lda #$18
  0x8d, 0x11, 0xff,       # sta $ff11
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x00, 0xff,       # sta $ff00
  0x8d, 0x01, 0xff,       # sta $ff01
  0x58,                   # cli
  0xee, 0x00, 0x0c,       # inc $0c00
  0x4c, 0x32, 0x10,       # jmp $1032
  0xee, 0x19, 0xff,       # irq: inc $ff19
  0xee, 0x47, 0x10,       # inc $1047
  0xad, 0x47, 0x10,       # lda $1047
  0x8d, 0x0e, 0xff,       # sta $ff0e
  0x4c, 0x00, 0x00,       # jmp the KERNAL's handler
  0x00                    # the pitch
].pack("C*").freeze

# The PET demo: 10 SYS1037, then the demo at $040D, which runs on every
# model. It runs VIA timer 1 free and the VIA's shift register free on
# CB2, the PET's sound, then loops, counting at $8000 and copying the
# timer and the keyboard row PIA 1 reads to $8001 and $8002, while the
# KERNAL's IRQ runs on.
PET_DEMO_PRG = [
  0x01, 0x04, # load address
  0x0b, 0x04, 0x0a, 0x00, 0x9e, 0x31, 0x30, 0x33, 0x37, 0x00, 0x00, 0x00,
  0x78,                   # sei
  0xa9, 0x50,             # lda #$50
  0x8d, 0x4b, 0xe8,       # sta $e84b
  0xa9, 0xff,             # lda #$ff
  0x8d, 0x44, 0xe8,       # sta $e844
  0x8d, 0x45, 0xe8,       # sta $e845
  0xa9, 0x0f,             # lda #$0f
  0x8d, 0x4a, 0xe8,       # sta $e84a
  0xa9, 0x20,             # lda #$20
  0x8d, 0x48, 0xe8,       # sta $e848
  0x58,                   # cli
  0xee, 0x00, 0x80,       # inc $8000
  0xad, 0x44, 0xe8,       # lda $e844
  0x8d, 0x01, 0x80,       # sta $8001
  0xad, 0x12, 0xe8,       # lda $e812
  0x8d, 0x02, 0x80,       # sta $8002
  0x4c, 0x26, 0x04        # jmp $0426
].pack("C*").freeze

# The machine bin/machine_diff's --family, --model, --mode and --ram
# build, the demo program each family runs, and the checkpoint that
# digests it. bin/snapshot_check digests its machines the same way.
module MachineFamilies
  NAMES = %w[c64 vic20 c128 plus4 pet cbm2 kim1].freeze

  # The families with no demo program yet, which run the boot and type
  # scenarios and media alone.
  NO_DEMO = %w[cbm2 kim1].freeze
  MODES = %w[c128 c64].freeze

  # What the type scenario types without --text.
  DEFAULT_TEXT = "print 6*7\r"

  # What the type scenario presses on the KIM-1's keypad without --text:
  # $1C00 into the NMI vector, LDA #$01 and JMP $0200 at $0200, GO, and ST
  # once it runs.
  KIM1_KEYS = "AD 17FA DA 00 + 1C AD 0200 DA A9 + 01 + 4C + 00 + 02 AD 0200 GO ST"

  module_function

  # The machine for the options, with a true drive plugged in if they ask.
  # `media` is the path a scenario attaches, or nil. A C64 without a model
  # named is built as TrueDrive builds it.
  def build(options, media)
    family = options[:family]
    return TrueDrive.computer(options) if family == "c64" && options[:model].nil?

    machine = family_machine(family, options, media)
    plug_drive(machine, options) if options[:true_drive]
    machine
  end

  def family_machine(family, options, media)
    case family
    when "vic20" then vic20(options, media)
    when "c128" then Badline::C128.new(model: options[:model] || "c128", mode: options[:mode].to_sym)
    when "plus4" then Badline::Plus4.new(model: options[:model] || "plus4", ram: options[:ram]&.to_i)
    when "pet" then Badline::PET.new(model: options[:model] || "8032", ram_kb: options[:ram]&.to_i)
    when "cbm2" then Badline::Machine.build(:cbm2, model: options[:model] || "610")
    when "kim1" then Badline::KIM1.new
    else Badline::Machine.build(:c64, model: options[:model])
    end
  end

  def vic20(options, media)
    ram = options[:ram]&.to_sym || (media ? Badline::Media.vic20_ram_for(media) : :unexpanded)
    machine = Badline::Machine.build(:vic20, model: options[:model] || "pal", ram:)
    machine.sound_source.record(rate: 44_100)
    machine
  end

  # A true 1541 on the serial bus, or on the PET and the CBM-II the
  # machine's own drive on the IEEE-488 bus.
  def plug_drive(machine, options)
    ieee = Badline::Media::TrueDrive::IEEE_FAMILIES.include?(machine.family)
    drive = ieee ? machine.plug_true_drive : Badline::Drives::Model1541.new
    drive.idle_skip = options[:idle_skip] if drive.respond_to?(:idle_skip=)
    machine.attach_drive1541(drive) unless ieee
  end

  def demo(options)
    case options[:family]
    when "vic20" then VIC20_DEMO_PRG
    when "c128" then options[:mode] == "c128" ? C128_DEMO_PRG : DEMO_PRG
    when "plus4" then PLUS4_DEMO_PRG
    when "pet" then PET_DEMO_PRG
    else DEMO_PRG
    end
  end

  # Loads the demo and runs it.
  def attach_demo(computer, options, dir)
    Badline::Media.attach(computer, write_demo(dir, options))
  end

  # Writes the demo into `dir` as demo.prg, and returns its path.
  def write_demo(dir, options)
    path = File.join(dir, "demo.prg")
    File.binwrite(path, demo(options))
    path
  end

  # What loads and runs the demo from device 8.
  def disk_text(options)
    case options[:family]
    when "vic20" then Badline::Media::Vic20Media.disk_autostart(VIC20_DEMO_PRG.bytes)
    when "pet" then Badline::Media::PETMedia::AUTOSTART
    else Badline::Media::AUTOSTART
    end
  end

  # What takes and parses the family's checkpoints.
  def checkpoint(options)
    case options[:family]
    when "vic20" then Badline::Support::Vic20Checkpoint
    when "c128" then Badline::Support::C128Checkpoint
    when "plus4" then Badline::Support::Plus4Checkpoint
    when "pet" then Badline::Support::PETCheckpoint
    when "cbm2" then p500?(options) ? Badline::Support::P500Checkpoint : Badline::Support::CBM2Checkpoint
    when "kim1" then Badline::Support::KIM1Checkpoint
    else Badline::Support::Checkpoint
    end
  end

  # Starts the type scenario: --text typed at the prompt, or pressed on
  # the KIM-1's keypad, KIM1_KEYS without it.
  def type(computer, options)
    text = options[:text]
    return computer.on_init { computer.type_text(text) } unless options[:family] == "kim1"

    computer.type_keys(text == DEFAULT_TEXT ? KIM1_KEYS : text)
  end

  # Whether the options name the P500 of the CBM-II family.
  def p500?(options) = Badline::CBM2::P500::Model.include?(options[:model])

  # The machine's checkpoint. The VIC-20 first drains the sound it records.
  def take(machine, options)
    machine.sound_source.drain_samples if options[:family] == "vic20"
    checkpoint(options).take(machine)
  end

  # The options that reach the run on another revision.
  def flags(options)
    ["--family", options[:family], *(["--model", options[:model]] if options[:model]),
     "--mode", options[:mode], *(["--ram", options[:ram]] if options[:ram])]
  end

  # --family, --model, --mode and --ram, and the scenarios, for --help.
  def define_options(opts, options)
    opts.on("--family FAMILY", "The machine: #{NAMES.join(', ')} (default: c64)") { |name| options[:family] = name }
    opts.on("--model MODEL", "The family's model, as Badline::Machine.build names it") do |model|
      options[:model] = model
    end
    opts.on("--mode MODE", "The C128's mode: #{MODES.join(', ')} (default: c128)") { |mode| options[:mode] = mode }
    opts.on("--ram RAM", "The VIC-20's RAM expansion (default: what the media needs), " \
                         "or the Plus/4's or the PET's RAM in K (default: the model's own)") do |ram|
      options[:ram] = ram
    end
    opts.separator ""
    opts.separator "Scenarios, on every family: boot, type (--text at the prompt), demo (a program built"
    opts.separator "here for the family, and for the C128's mode) and disk (the demo loaded from a host"
    opts.separator "directory as device 8). Anything else is media for Badline::Media.attach. The"
    opts.separator "comment at the top of bin/machine_diff says what each family's demo does and digests."
  end

  # Why the options don't make a machine, or nil.
  def invalid(options)
    family = options[:family]
    return "no family named #{family} (#{NAMES.join(', ')})" unless NAMES.include?(family)
    return "no C128 mode named #{options[:mode]} (#{MODES.join(', ')})" unless MODES.include?(options[:mode])

    return unless options[:ram]
    return "--ram is the VIC-20's, the Plus/4's or the PET's" unless %w[vic20 plus4 pet].include?(family)
    return if family == "vic20"

    sizes = family == "pet" ? Badline::PET::Model::RAM_SIZES : Badline::Plus4::Model::RAM_SIZES
    return if sizes.include?(options[:ram].to_i)

    "no #{family == 'pet' ? 'PET' : 'Plus/4'} RAM size of #{options[:ram]}K (#{sizes.join(', ')})"
  end
end
