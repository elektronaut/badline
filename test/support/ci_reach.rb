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
  VIC20 = %w[testbench-vic20 testbench-vic20-ntsc drive-scenarios].freeze
  C128 = %w[testbench-c128c64 testbench-c128 testbench-c128-z80 drive-scenarios].freeze
  PLUS4 = %w[testbench-plus4 testbench-c16 testbench-plus4-ntsc lorenz-plus4 drive-scenarios].freeze
  PET = %w[testbench-pet testbench-pet-discrete].freeze
  # The P500 runs on the B series' bus, CPU, TPIs, CIA, SID and ACIA.
  P500 = %w[testbench-cbm5x0].freeze
  CBM2 = (%w[testbench-cbm2] + P500).freeze
  VIC = %w[testbench testbench-vicii-new testbench-ntsc testbench-ntsc-vicii-new testbench-drean
           testbench-interrupts testbench-irqdma testbench-general testbench-expansions testbench-carts
           testbench-c128c64 testbench-c128].freeze
  CIA = %w[lorenz testbench-cia testbench-cia-new testbench-ntsc-cia-new testbench-interrupts testbench-irqdma
           testbench-general testbench-c128c64 testbench-c128 drive-scenarios].freeze
  SID = %w[sid sid-8580 spinel:check_sid].freeze
  DRIVES = %w[testbench-drive drive-scenarios testbench-vic20 testbench-vic20-ntsc].freeze
  # The PET's VIA is a Chips::VIA.
  VIA = (DRIVES + PET).freeze
  CARTRIDGES = %w[testbench-carts testbench-expansions testbench-general].freeze
  # Every family's keyboard is an Input::Keyboard, which the C64, VIC-20
  # and C128 read their joysticks beside through the CIA and VIA ports and
  # the C128 types through, and the paddles and mouse feed the SID's pots.
  INPUT = (C64 + VIC20 + C128 + PLUS4 + PET + CBM2 + SID).uniq.freeze
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
    ["test/support/{moo_reader,m6809_*}.rb", []],
    ["test/support/testbench_cbm2{,_machine}.rb", CBM2],
    ["test/support/testbench_p500_machine.rb", P500],
    ["spinel/p500_{boot,testbench,snapshot}.rb", P500 + %w[spinel:check]],
    ["bin/{snapshot_check,machine_diff,profile,benchmark,sidwavecheck,sidwavefit,suites_status}", []],
    ["{bin/drive_scenarios,test/support/drive_scenarios*.rb}", %w[drive-scenarios drive-scenarios-cpm]],
    ["{native,exe}/**/*", []],
    ["{.rubocop.yml,.rubocop_todo.yml,.gitignore,LICENSE*,*.md}", []],
    ["lib/badline/**/{saved_state,keyed_state,keyed_parts,keyed_modules,keyed_sprites}.rb", []],
    ["lib/badline/{frontend,audio,options,snapshot}/**/*", []],
    ["lib/badline/{frontend,audio,options,snapshot,sdl,ffi,status,version}.rb", []],
    ["lib/badline/support/{vic20,c128,plus4,pet}_checkpoint.rb", []],
    ["lib/badline/roms/README", []],
    ["lib/badline/roms/pet/{superpet-*,characters-superpet}.rom", []],
    ["lib/badline/roms/pet/**/*", PET],
    ["lib/badline/roms/cbm2/p500-*", P500],
    ["lib/badline/roms/cbm2/**/*", CBM2],
    ["lib/badline/{machine/ieee_drives.rb,drives/ieee_models.rb}", (PET + CBM2 + %w[drive-scenarios]).uniq],
    ["lib/badline/cbm2/{p500.rb,p500/control_ports.rb}", P500 + %w[drive-scenarios]],
    ["lib/badline/{cbm2/p500.rb,cbm2/p500/**/*,support/p500_checkpoint.rb}", P500],
    ["lib/badline/{cbm2.rb,cbm2/ieee_ports.rb,cbm2/ieee_traps.rb,cbm2/ieee_drive.rb}", CBM2 + %w[drive-scenarios]],
    ["lib/badline/{cbm2.rb,cbm2/**/*,chips/tpi.rb,chips/tpi/**/*,support/cbm2_checkpoint.rb}", CBM2],
    ["lib/badline/roms/{8050,1001,4040,9060}/**/*", %w[drive-scenarios]],
    # No suite runs the KIM-1 yet.
    ["lib/badline/{kim1.rb,kim1/**/*,roms/kim1/**/*,support/kim1_checkpoint.rb}", []],
    ["lib/badline/chips/cpu{.rb,/**/*}", ALL],
    ["lib/badline/chips/cia{.rb,/**/*}", CIA + CBM2],
    ["lib/badline/chips/vic{.rb,/**/*}", VIC + P500],
    ["lib/badline/chips/sid{.rb,/**/*}", SID + CBM2],
    ["lib/badline/chips/via{.rb,/**/*}", VIA],
    ["lib/badline/chips/vic_i{.rb,/**/*}", VIC20],
    ["lib/badline/chips/{z80,vdc}{.rb,/**/*}", C128],
    # No machine has a 6809 yet.
    ["lib/badline/chips/m6809{.rb,/**/*}", []],
    # The 6532 and 6530 of the 8050 and 8250, which only the PET's drive
    # scenarios plug in.
    ["lib/badline/chips/{riot,rriot}{.rb,/**/*}", %w[drive-scenarios]],
    ["lib/badline/c64/{cartridge,reu,banked_ram}{.rb,/**/*}", CARTRIDGES],
    ["lib/badline/{c64.rb,c64/**/*}", C64 + %w[testbench-c128c64]],
    ["lib/badline/{vic20.rb,vic20/**/*}", VIC20],
    ["lib/badline/{c128.rb,c128/**/*}", C128],
    ["lib/badline/chips/acia{.rb,/**/*}", PLUS4 + CBM2],
    ["lib/badline/{plus4.rb,plus4/**/*,chips/ted.rb,chips/ted/**/*,chips/tia.rb}", PLUS4],
    ["lib/badline/{pet.rb,pet/ieee_ports.rb,pet/ieee_traps.rb,pet/ieee_drive.rb}", PET + %w[drive-scenarios]],
    ["lib/badline/chips/crtc{.rb,/**/*}", PET + %w[testbench-cbm2]],
    ["lib/badline/{pet.rb,pet/**/*,chips/pia.rb,chips/pia/**/*}", PET],
    ["lib/badline/kernal_trap/{ieee,ieee_layout}.rb", PET + CBM2 + %w[drive-scenarios]],
    ["lib/badline/drives/ieee_bus.rb", PET + %w[drive-scenarios]],
    ["lib/badline/{drives/model2031.rb,drives/model2031/**/*,roms/dos2031.rom}", PET + %w[drive-scenarios]],
    ["lib/badline/drives/model8050{.rb,/**/*}", %w[drive-scenarios]],
    ["lib/badline/{storage/d90_image.rb,drives/model9060{.rb,/**/*}}", %w[drive-scenarios]],
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
