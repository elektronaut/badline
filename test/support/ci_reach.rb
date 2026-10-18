# frozen_string_literal: true

require_relative "suites"

# The suites a pull request's changed files can move, so its CI runs those
# and leaves the rest to suites.yml, which runs every suite on main every
# two hours. Each path goes to the first rule whose pattern matches it. A
# path no rule names reaches every suite.
module CIReach
  ALL = :all

  C64 = %w[testbench lorenz sid sid-8580 testbench-cia testbench-interrupts testbench-irqdma testbench-cpu
           testbench-carts testbench-cia-new testbench-vicii-new testbench-general testbench-expansions
           testbench-drive testbench-ntsc testbench-ntsc-vicii-new testbench-ntsc-cia-new testbench-drean
           drive-scenarios].freeze
  VIC20 = %w[testbench-vic20 drive-scenarios].freeze
  C128 = %w[testbench-c128c64 testbench-c128 testbench-c128-z80 drive-scenarios].freeze
  PLUS4 = %w[testbench-plus4 testbench-c16 testbench-plus4-ntsc lorenz-plus4 drive-scenarios].freeze
  PET = %w[testbench-pet testbench-pet-discrete].freeze
  VIC = %w[testbench testbench-vicii-new testbench-ntsc testbench-ntsc-vicii-new testbench-drean
           testbench-interrupts testbench-irqdma testbench-general testbench-expansions testbench-carts
           testbench-c128c64 testbench-c128].freeze
  CIA = %w[lorenz testbench-cia testbench-cia-new testbench-ntsc-cia-new testbench-interrupts testbench-irqdma
           testbench-general testbench-c128c64 testbench-c128 drive-scenarios].freeze
  SID = %w[sid sid-8580 spinel:check_sid].freeze
  DRIVES = %w[testbench-drive drive-scenarios testbench-vic20].freeze
  # The PET's VIA is a Chips::VIA.
  VIA = (DRIVES + PET).freeze
  CARTRIDGES = %w[testbench-carts testbench-expansions testbench-general].freeze
  # Every family's keyboard is an Input::Keyboard, which the C64, VIC-20
  # and C128 read their joysticks beside through the CIA and VIA ports and
  # the C128 types through, and the paddles and mouse feed the SID's pots.
  INPUT = (C64 + VIC20 + C128 + PLUS4 + PET + SID).uniq.freeze
  # Media.attach loads the C64 and C128 testbench rows' programs and
  # cartridges, the SID testprogs and every drive scenario. The VIC-20 and
  # Plus/4 testbenches load their programs themselves, and the Lorenz
  # chains mount their disks.
  MEDIA = (C64 - %w[lorenz] + C128 + %w[spinel:check_sid]).uniq.freeze

  # Patterns as File.fnmatch takes them with FNM_PATHNAME and FNM_EXTGLOB,
  # in order, each mapped to the suites a change there can move.
  RULES = [
    ["{spec,doc}/**/*", []],
    ["test/test_*.rb", []],
    ["test/support/{ci_matrix,ci_reach,suites_status,snapshot_*,machine_families}.rb", []],
    ["bin/{snapshot_check,machine_diff,profile,benchmark,sidwavecheck,sidwavefit,suites_status}", []],
    ["{native,exe}/**/*", []],
    ["{.rubocop.yml,.rubocop_todo.yml,.gitignore,LICENSE*,*.md}", []],
    ["lib/badline/**/{saved_state,keyed_state,keyed_parts,keyed_modules,keyed_sprites}.rb", []],
    ["lib/badline/{frontend,audio,options,snapshot}/**/*", []],
    ["lib/badline/{frontend,audio,options,snapshot,sdl,ffi,status,version}.rb", []],
    ["lib/badline/support/{vic20,c128,plus4,pet}_checkpoint.rb", []],
    ["lib/badline/roms/README", []],
    ["lib/badline/roms/pet/**/*", PET],
    ["lib/badline/chips/cpu{.rb,/**/*}", ALL],
    ["lib/badline/chips/cia{.rb,/**/*}", CIA],
    ["lib/badline/chips/vic{.rb,/**/*}", VIC],
    ["lib/badline/chips/sid{.rb,/**/*}", SID],
    ["lib/badline/chips/via{.rb,/**/*}", VIA],
    ["lib/badline/chips/vic_i{.rb,/**/*}", VIC20],
    ["lib/badline/chips/{z80,vdc}{.rb,/**/*}", C128],
    ["lib/badline/c64/{cartridge,reu,banked_ram}{.rb,/**/*}", CARTRIDGES],
    ["lib/badline/{c64.rb,c64/**/*}", C64 + %w[testbench-c128c64]],
    ["lib/badline/{vic20.rb,vic20/**/*}", VIC20],
    ["lib/badline/{c128.rb,c128/**/*}", C128],
    ["lib/badline/{plus4.rb,plus4/**/*,chips/ted.rb,chips/ted/**/*,chips/tia.rb,chips/acia.rb,chips/acia/**/*}", PLUS4],
    ["lib/badline/{pet.rb,pet/ieee_ports.rb,pet/ieee_traps.rb,pet/ieee_drive.rb}", PET + %w[drive-scenarios]],
    ["lib/badline/{pet.rb,pet/**/*,chips/pia.rb,chips/pia/**/*,chips/crtc.rb,chips/crtc/**/*}", PET],
    ["lib/badline/{kernal_trap/ieee,kernal_trap/ieee_layout,drives/ieee_bus}.rb", PET + %w[drive-scenarios]],
    ["lib/badline/{drives/model2031.rb,drives/model2031/**/*,roms/dos2031.rom}", PET + %w[drive-scenarios]],
    ["lib/badline/input{.rb,/**/*}", INPUT],
    ["lib/badline/media{.rb,/**/*}", MEDIA],
    ["lib/badline/drives/model1541{.rb,/**/*}", DRIVES],
    ["lib/badline/drives/{model1571,model1581}{.rb,/**/*}", %w[drive-scenarios testbench-c128c64 testbench-c128]],
    ["lib/badline/drives/{engine,serial_bus}{.rb,/**/*}", DRIVES + %w[testbench-c128c64 testbench-c128]],
    ["test/baselines/*.txt", :baseline]
  ].freeze

  FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

  # Every lib/ change also runs spinel:check, which compiles the boot
  # harnesses of every family and checks them against CRuby.
  LIB_CHECK = %w[spinel:check].freeze

  module_function

  # The suites and checks the files reach, or ALL.
  def suites(files)
    reached = files.flat_map do |file|
      found = reach(file)
      return ALL if found == ALL

      file.start_with?("lib/") ? found + LIB_CHECK : found
    end
    reached.uniq.sort
  end

  def reach(file)
    _, suites = RULES.find { |pattern, _| File.fnmatch?(pattern, file, FLAGS) }
    return ALL if suites.nil?
    return [File.basename(file, ".txt")] if suites == :baseline

    suites
  end
end
