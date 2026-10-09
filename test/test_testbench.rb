# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

TESTBENCH = File.expand_path("../bin/testbench", __dir__)
load TESTBENCH unless defined?(Testbench)

class TestTestbenchTestlist < Minitest::Test
  def parse(line)
    Testbench::Testlist.parse(line)
  end

  def test_parses_an_included_subtree
    test = parse("../CIA/irqdelay/,cia-irq-1.prg,exitcode,4000000,cia-old\n")

    assert_equal "CIA/irqdelay/cia-irq-1.prg", test.id
    assert_equal 4_000_000, test.timeout
  end

  def test_keeps_every_modelled_subsystem
    %w[VICII CIA interrupts CPU].each do |subtree|
      refute_nil parse("../#{subtree}/x/,t.prg,exitcode,1000")
    end
  end

  def test_keeps_the_machine_level_subtrees
    assert_equal "C64/bankio/bankio.prg", parse("../C64/bankio/,bankio.prg,exitcode,1000").id
    assert_equal "general/fuxxortest/ef1-nmi.prg", parse("../general/fuxxortest,ef1-nmi.prg,exitcode,1000").id
  end

  def test_leaves_the_6526_half_of_lorenz_to_bin_lorenz
    assert_nil parse("../general/Lorenz-2.15/src/,cia1ta.prg,exitcode,1000")
    refute_nil parse("../general/Lorenz-2.15/src/,cia1tanew.prg,exitcode,1000,cia-new")
  end

  def test_drops_rows_that_need_a_true_drive
    assert_nil parse("../general/fuxxortest,ef2-inst1.prg,exitcode,1000")
    assert_nil parse("../general/fuxxortest,test-fuxxored.prg,exitcode,1000")
  end

  def test_drops_subtrees_for_unmodelled_hardware
    assert_nil parse("../REU/mirrors/,t.prg,exitcode,1000")
    assert_nil parse("../SID/foo/,t.prg,exitcode,1000")
  end

  def test_drops_decimalmode_covered_by_singlesteptests
    assert_nil parse("../CPU/decimalmode/,cpu_decimal.prg,exitcode,1000")
  end

  def test_drops_types_the_runner_cannot_score
    assert_nil parse("../CIA/tod/,t.prg,analyzer,0")
    assert_nil parse("../CPU/cpuport/,t.prg,interactive,0")
  end

  def test_drops_options_the_emulator_does_not_model
    assert_nil parse("../VICII/border/,t.prg,exitcode,1000,isepic")
  end

  def test_runs_the_cia_old_half_of_a_doubled_row_on_the_old_chip
    assert_equal :mos6526, parse("../CIA/tod/,t.prg,exitcode,1000,cia-old").cia_model
  end

  def test_runs_the_cia_new_half_of_a_doubled_row_on_the_new_chip
    assert_equal :mos6526a, parse("../CIA/tod/,t.prg,exitcode,1000,cia-new").cia_model
  end

  def test_runs_an_untagged_row_on_the_old_chip
    assert_equal :mos6526, parse("../CIA/tod/,t.prg,exitcode,1000").cia_model
  end

  def test_runs_the_vicii_new_half_of_a_doubled_row_on_the_new_chip
    assert_equal :mos8565, parse("../VICII/lp-trigger/,t.prg,exitcode,1000,vicii-pal,vicii-new").vic_model
  end

  def test_runs_the_vicii_old_half_of_a_doubled_row_on_the_old_chip
    assert_equal :mos6569, parse("../VICII/videomode/,t.prg,screenshot,1000,vicii-pal,vicii-old").vic_model
  end

  def test_runs_an_untagged_row_on_the_old_vicii
    assert_equal :mos6569, parse("../VICII/border/,t.prg,exitcode,1000").vic_model
  end

  def test_compares_an_8565_row_against_the_8565_reference
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "references"))
      %w[t.prg.png t.prg-8565.png].each { |name| FileUtils.touch(File.join(dir, "references", name)) }
      new, old = %w[vicii-new vicii-old].map { |option| Testbench::TestCase.new(dir, "t.prg", "screenshot", 1000, [option]) }

      assert_equal File.join(dir, "references", "t.prg-8565.png"), new.reference
      assert_equal File.join(dir, "references", "t.prg.png"), old.reference
    end
  end

  def test_falls_back_to_the_generic_reference_without_an_8565_one
    Dir.mktmpdir do |dir|
      test = Testbench::TestCase.new(dir, "t.prg", "screenshot", 1000, ["vicii-new"])

      assert_equal File.join(dir, "references", "t.prg.png"), test.reference
    end
  end

  def test_ignores_comments_and_blank_lines
    assert_nil parse("# ../CIA/tod/,t.prg,exitcode,1000")
    assert_nil parse("   \n")
  end
end

class TestTestbenchCartridges < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    write_crt("standard.crt", 0)
    write_crt("expert.crt", 6)
    File.binwrite(File.join(@dir, "t.prg"), "\x01\x08".b)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_crt(name, hardware_type)
    header = "C64 CARTRIDGE   ".b + [0x40, 0x0100, hardware_type].pack("Nnn") + "\x00\x01".b
    File.binwrite(File.join(@dir, name), header.ljust(0x40, "\x00"))
  end

  def parse(options, prg: "")
    Testbench::Testlist.parse("#{@dir}/,#{prg},exitcode,100000,#{options}")
  end

  def test_names_a_row_after_its_cartridge
    assert_equal "#{@dir}/standard.crt", parse("mountcrt:standard.crt").id
  end

  def test_keeps_the_cartridge_from_any_subtree
    assert_equal "standard.crt", parse("mountcrt:standard.crt").cartridge
  end

  def test_drops_a_cartridge_type_without_a_mapper
    assert_nil parse("mountcrt:expert.crt")
  end

  def test_drops_a_missing_cartridge
    assert_nil parse("mountcrt:missing.crt")
  end

  def test_names_a_row_that_loads_a_program_after_both
    assert_equal "#{@dir}/t.prg+standard.crt", parse("mountcrt:standard.crt", prg: "t.prg").id
  end

  def test_drops_a_missing_program_loaded_alongside_a_cartridge
    assert_nil parse("mountcrt:standard.crt", prg: "missing.prg")
  end

  def test_drops_a_cartridge_that_needs_a_memory_expansion
    assert_nil parse("reu512k,mountcrt:standard.crt")
  end

  def test_drops_a_cartridge_row_that_also_mounts_a_disk
    FileUtils.touch(File.join(@dir, "disk.d64"))

    assert_nil parse("mountcrt:standard.crt,mountd64:disk.d64")
  end

  def test_a_plain_row_is_not_a_cartridge_row
    assert_nil Testbench::Testlist.parse("../CIA/tod/,t.prg,exitcode,1000").cartridge
  end

  def test_a_cartridge_row_is_listed_under_carts
    rows = Testbench::Rows.new(carts: true, models: Testbench::DEFAULT_MODELS, expansions: false, drive: nil)

    assert_includes rows, parse("mountcrt:standard.crt")
  end
end

class TestTestbenchDrive < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @disk = File.join(@dir, "disk.d64")
    FileUtils.touch(@disk)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def parse(line)
    Testbench::Testlist.parse(line)
  end

  def test_runs_a_drive_row_with_a_true_drive
    assert_predicate parse("../drive/rpm/,rpm.prg,exitcode,1000"), :drive?
  end

  def test_keeps_the_disk_a_row_mounts
    assert_equal @disk, parse("../drive/readtest/,t.prg,exitcode,1000,mountd64:#{@disk}").disk_path
  end

  def test_a_drive_row_hands_the_engine_its_drive_and_disk
    test = parse("../drive/readtest/,t.prg,exitcode,1000,mountd64:#{@disk}")

    assert Testbench::Engine.spec(test).end_with?("\tpal\tdrive\t#{@disk}\t\n")
  end

  def test_a_row_that_loads_from_its_disk_types_its_name
    test = parse("../C64/autostart/defaults/,test.prg,exitcode,1000,mountd64:#{@disk}")

    assert Testbench::Engine.spec(test).end_with?("\tdrive\t#{@disk}\ttest\n")
  end

  def test_a_row_without_its_disk_injects_its_program
    assert_equal "", parse("../C64/autostart/defaults/,test.prg,exitcode,1000").load_name
  end

  def test_runs_a_row_that_mounts_a_disk_with_a_true_drive
    assert_predicate parse("../VICII/x/,t.prg,exitcode,1000,mountd64:#{@disk}"), :drive?
  end

  def test_drops_a_missing_disk
    assert_nil parse("../drive/readtest/,t.prg,exitcode,1000,mountd64:#{@dir}/missing.d64")
  end

  def test_drops_a_disk_outside_the_included_subtrees
    assert_nil parse("../SID/foo/,t.prg,exitcode,1000,mountd64:#{@disk}")
  end

  def test_keeps_the_g64_a_row_mounts
    g64 = File.join(@dir, "skew.g64")
    FileUtils.touch(g64)
    test = parse("../drive/skew/,t.prg,exitcode,1000,mountg64:#{g64}")

    assert_equal [:drive, g64], [test.drive_kind, test.disk_path]
  end

  def test_drops_the_image_formats_the_drive_cannot_read
    assert_nil parse("../drive/skew/,t.prg,exitcode,1000,mountp64:skew.p64")
  end

  def test_a_plain_row_has_no_drive
    refute_predicate parse("../CIA/tod/,t.prg,exitcode,1000"), :drive?
  end

  def test_lists_each_row_under_one_kind_of_run
    rows = ["../CIA/tod/,t.prg,exitcode,1000", "../drive/rpm/,t.prg,exitcode,1000",
            "../VICII/x/,t.prg,exitcode,1000,mountd64:#{@disk}"]

    assert_equal([nil, :drive, :drive], rows.map { |row| parse(row).drive_kind })
  end

  def test_lists_the_1541_testsuite_only_under_its_own_flag
    test = parse("../drive/1541-testsuite,1541-testsuite.prg,exitcode,2220000000,mountd64:#{@disk}")

    assert_equal [:testsuite, true], [test.drive_kind, test.drive?]
  end

  def test_keeps_a_row_that_writes_the_disk_under_drive
    assert_equal :drive, parse("../drive/format/,format.prg,exitcode,88000000,mountd64:#{@disk}").drive_kind
  end

  def test_only_a_drive_run_takes_a_drive_row
    test = parse("../drive/rpm/,t.prg,exitcode,1000")
    rows = Testbench::Rows.new(carts: false, models: Testbench::DEFAULT_MODELS, expansions: false, drive: :drive)

    refute_includes Testbench::Rows.plain, test
    assert_includes rows, test
  end

  def test_a_drive_row_gets_twice_the_deadline
    drive, plain = ["../drive/rpm", "../CIA/tod"].map do |dir|
      Testbench::TestCase.new(dir, "t.prg", "exitcode", 10_000_000, [])
    end

    assert_equal [320, 190], [drive.deadline, plain.deadline]
  end
end

class TestTestbenchNTSC < Minitest::Test
  def parse(options)
    Testbench::Testlist.parse("../VICII/border/,t.prg,screenshot,1000,#{options}")
  end

  def test_runs_a_vicii_ntsc_row_on_the_6567r8
    assert_equal :ntsc, parse("vicii-ntsc").region
  end

  def test_runs_a_vicii_ntscold_row_on_the_6567r56a
    assert_equal :ntscold, parse("vicii-ntscold").region
  end

  def test_runs_an_untagged_row_on_pal
    assert_equal :pal, parse("vicii-old").region
  end

  def test_only_an_ntsc_run_takes_an_ntsc_row
    test = parse("vicii-ntsc")
    rows = Testbench::Rows.new(carts: false, models: Testbench::DEFAULT_MODELS, expansions: false, drive: nil,
                               standard: :ntsc)

    refute_includes Testbench::Rows.plain, test
    assert_includes rows, test
  end

  # modesplit is listed for PAL, the 6567R8 and the 6567R56A under one id.
  def test_numbers_a_program_listed_for_both_ntsc_chips
    tests = Testbench::Testlist.numbered([parse(""), parse("vicii-ntsc"), parse("vicii-ntscold")])

    assert_equal ["VICII/border/t.prg", "VICII/border/t.prg", "VICII/border/t.prg#2"], tests.map(&:key)
  end

  def test_compares_an_ntsc_row_against_its_ntsc_then_8562_reference
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "references"))
      %w[t.prg.png t.prg-ntsc.png t.prg-8562.png].each { |name| FileUtils.touch(File.join(dir, "references", name)) }
      old, new, older = [%w[vicii-ntsc], %w[vicii-ntsc vicii-new], %w[vicii-ntscold]].map do |options|
        Testbench::TestCase.new(dir, "t.prg", "screenshot", 1000, options)
      end

      assert_equal File.join(dir, "references", "t.prg-ntsc.png"), old.reference
      assert_equal File.join(dir, "references", "t.prg-8562.png"), new.reference
      assert_equal File.join(dir, "references", "t.prg.png"), older.reference
    end
  end

  def test_crops_an_ntsc_screenshot_from_line_28_through_the_next_frame
    vic = Badline::VIC.new(region: Badline::Region::NTSC)
    vic.display[(28 * vic.width) + 96] = 5
    vic.display[(11 * vic.width) + 96] = 7
    rows = Testbench.screenshot(vic)

    assert_equal [247, 5, 7], [rows.length, rows.first.first, rows.last.first]
  end
end

class TestTestbenchDrean < Minitest::Test
  def parse(line)
    Testbench::Testlist.parse(line)
  end

  def drean_rows
    Testbench::Rows.new(carts: false, models: Testbench::DEFAULT_MODELS, expansions: false, drive: nil,
                        standard: :drean)
  end

  def test_runs_a_vicii_drean_row_on_the_drean
    assert_equal :drean, parse("../VICII/border/,t.prg,exitcode,1000,vicii-drean").region
  end

  # The testlist comments its one Drean row out until a testbench can run
  # the 6572.
  def test_reads_a_commented_out_vicii_drean_row
    test = parse("#../VICII/split-tests/spritescan/,spritescan_drean.prg,exitcode,1000000000,vicii-drean")

    assert_equal ["VICII/split-tests/spritescan/spritescan_drean.prg", :drean], [test.id, test.region]
  end

  def test_leaves_other_commented_out_rows_alone
    assert_nil parse("#../VICII/border/,t.prg,exitcode,1000,vicii-ntsc")
  end

  def test_only_a_drean_run_takes_a_drean_row
    test = parse("../VICII/border/,t.prg,exitcode,1000,vicii-drean")

    refute_includes Testbench::Rows.plain, test
    assert_includes drean_rows, test
  end

  def test_a_drean_run_takes_no_pal_row
    refute_includes drean_rows, parse("../VICII/border/,t.prg,exitcode,1000")
  end

  def test_builds_a_drean_machine
    assert_equal Badline::Region::DREAN, Testbench.region_profile(:drean)
  end

  def test_crops_a_drean_screenshot_as_pal
    vic = Badline::VIC.new(region: Badline::Region::DREAN)
    vic.display[(16 * vic.width) + 96] = 5
    rows = Testbench.screenshot(vic)

    assert_equal [272, 5], [rows.length, rows.first.first]
  end
end

class TestTestbenchExpansions < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    File.binwrite(File.join(@dir, "t.prg"), "\x01\x08".b)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def parse(options, prg: "t.prg")
    Testbench::Testlist.parse("#{@dir}/,#{prg},exitcode,100000,#{options}")
  end

  def test_keeps_a_row_for_each_emulated_expansion
    %w[geo512k plus60k plus256k].each do |option|
      assert_equal option, parse(option).expansion
    end
  end

  def test_drops_a_missing_program
    assert_nil parse("geo512k", prg: "missing.prg")
  end

  def test_keeps_a_row_for_each_reu_size
    %w[reu128k reu512k reu16m].each do |option|
      assert_equal option, parse(option).expansion
    end
  end

  def test_drops_rows_for_expansions_badline_does_not_emulate
    assert_nil parse("isepic")
  end

  def test_a_plain_row_has_no_expansion
    assert_nil Testbench::Testlist.parse("../CIA/tod/,t.prg,exitcode,1000").expansion
  end

  def test_only_an_expansions_run_takes_an_expansion_row
    test = parse("geo512k")

    rows = Testbench::Rows.new(carts: false, models: Testbench::DEFAULT_MODELS, expansions: true, drive: nil)

    refute_includes Testbench::Rows.plain, test
    assert_includes rows, test
  end
end

class TestTestbenchMachine < Minitest::Test
  def test_sizes_an_reu_in_k
    assert_equal 128, Testbench.reu_size("reu128k")
    assert_equal 16_384, Testbench.reu_size("reu16m")
  end

  def test_fits_no_reu_for_other_expansions
    assert_nil Testbench.reu_size("geo512k")
    assert_nil Testbench.reu_size(nil)
  end
end

class TestTestbenchVic20 < Minitest::Test
  # 10 POKE37135,0, which reports a pass through $910F.
  REPORTS_PASS = [0x01, 0x10, 0x0e, 0x10, 0x0a, 0x00, 0x97, *"37135,0".bytes, 0x00, 0x00, 0x00].freeze

  # Starts itself from BLK5 and reports a pass: LDA #$00, STA $910F, JMP
  # to itself.
  AUTOSTART = [0x09, 0xa0, 0x09, 0xa0, 0x41, 0x30, 0xc3, 0xc2, 0xcd,
               0xa9, 0x00, 0x8d, 0x0f, 0x91, 0x4c, 0x0e, 0xa0].freeze

  def setup
    @dir = Dir.mktmpdir
    File.binwrite(File.join(@dir, "t.prg"), REPORTS_PASS.pack("C*"))
    write_crt("cart.crt", AUTOSTART + Array.new(256 - AUTOSTART.length, 0xea))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_crt(name, rom)
    header = "VIC20 CARTRIDGE ".b + [0x40, 0x0100, 0, 0, 0, 0].pack("NnnCCCx5") + ["Generic"].pack("a32")
    chip = ["CHIP", 0x10 + rom.length, 0, 0, 0xa000, rom.length].pack("a4Nn4") + rom.pack("C*")
    File.binwrite(File.join(@dir, name), header + chip)
  end

  def parse(options, prg: "t.prg", type: "exitcode")
    Testbench::Vic20Testlist.parse("#{@dir}/,#{prg},#{type},100000,#{options}")
  end

  def test_runs_a_row_on_the_vic20
    assert_predicate parse("vic20-unexp"), :vic20?
    refute_predicate Testbench::Testlist.parse("../CIA/tod/,t.prg,exitcode,1000"), :vic20?
  end

  def test_fits_the_ram_each_option_asks_for
    assert_equal :unexpanded, parse("vic20-unexp").ram_configuration
    assert_equal :unexpanded, parse("expect:error").ram_configuration
    assert_equal :"8k", parse("vic20-8k").ram_configuration
    assert_equal :all, parse("vic20-32k").ram_configuration
  end

  def test_takes_only_exitcode_rows
    assert_nil parse("vic20-8k", type: "screenshot")
    assert_nil parse("", type: "interactive")
  end

  def test_drops_a_row_that_asks_for_a_georam
    assert_nil parse("vic20-8k,geo512k")
  end

  def test_drops_a_missing_program
    assert_nil parse("vic20-8k", prg: "missing.prg")
  end

  def test_names_a_cartridge_row_after_its_cartridge
    assert_equal "#{@dir}/cart.crt", parse("mountcrt:cart.crt", prg: "").id
  end

  def test_drops_a_missing_cartridge
    assert_nil parse("mountcrt:missing.crt", prg: "")
  end

  def test_hands_the_engine_its_ram_configuration
    assert Testbench::Engine.spec(parse("vic20-8k")).end_with?("\t#{@dir}\t8k\n")
  end

  def test_runs_a_program_from_the_start_of_basic
    test = parse("vic20-unexp")

    assert_equal 0, test.run_vic20(test.vic20_machine).first
  end

  def test_starts_a_cartridge_from_power_on
    test = parse("mountcrt:cart.crt", prg: "")
    machine = test.vic20_machine

    assert_equal [0, 0], [machine.cycles, test.run_vic20(machine).first]
  end

  def test_reads_the_text_screen_where_the_kernal_keeps_it
    machine = Testbench.vic20_machine(:unexpanded, true)

    assert_equal "**** cbm basic v2 ****", Testbench.vic20_screen_text(machine)[0]
  end
end

class TestTestbenchC128 < Minitest::Test
  def parse(options, dir: "../VICII/border", prg: "t.prg", type: "screenshot")
    Testbench::C128Testlist.parse("#{dir}/,#{prg},#{type},1000,#{options}")
  end

  def test_runs_a_row_on_the_c128
    assert_predicate parse(""), :c128?
    refute_predicate Testbench::Testlist.parse("../VICII/border/,t.prg,exitcode,1000"), :c128?
  end

  def test_picks_the_board_the_cias_and_the_video_standard_ask_for
    models = ["", "cia-new", "vicii-ntsc", "vicii-ntsc,cia-new"].map { |options| parse(options).c128_model }

    assert_equal %w[c128 c128dcr c128ntsc c128dcrntsc], models
  end

  def test_drops_the_rows_the_makefile_drops_for_x128
    %w[vicii-ntscold vicii-drean plus60k plus256k].each { |option| assert_nil parse(option) }
  end

  def test_numbers_a_program_listed_for_pal_and_ntsc
    tests = Testbench::C128Testlist.numbered([parse("vicii-new"), parse("vicii-ntsc")])

    assert_equal ["VICII/border/t.prg", "VICII/border/t.prg#2"], tests.map(&:key)
  end

  def test_drops_a_row_that_asks_for_the_old_vicii
    assert_nil parse("vicii-pal,vicii-old")
  end

  def test_compares_against_the_8565_reference_like_a_vicii_new_row
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "references"))
      %w[t.prg.png t.prg-8565.png].each { |name| FileUtils.touch(File.join(dir, "references", name)) }
      test = Testbench::TestCase.new(dir, "t.prg", "screenshot", 1000, [])
      test.family = :c128

      assert_equal File.join(dir, "references", "t.prg-8565.png"), test.reference
    end
  end

  def test_takes_the_curated_subtrees
    %w[VICII CPU interrupts C64 general].each { |subtree| refute_nil parse("", dir: "../#{subtree}/x") }
    refute_nil parse("", dir: "./selftest", prg: "c64-pass.prg")
  end

  def test_leaves_the_subtrees_the_c64_suites_cover
    %w[CIA SID REU drive CPU/decimalmode interrupts/irqdma].each do |subtree|
      assert_nil parse("", dir: "../#{subtree}")
    end
  end

  def test_takes_the_lorenz_cpuport_row_as_the_c128s_build
    lorenz = "../general/Lorenz-2.15/src"

    assert_equal "general/Lorenz-2.15/src/cpuport128.prg", parse("", dir: lorenz, prg: "cpuport.prg").id
    assert_nil parse("", dir: lorenz, prg: "cia1ta.prg")
  end

  def test_drops_rows_that_ask_for_an_expansion_or_a_disk
    assert_nil parse("reu512k")
    assert_nil parse("geo512k")
    assert_nil parse("mountd64:t.d64")
  end

  def test_hands_the_engine_its_model
    assert Testbench::Engine.spec(parse("cia-new", type: "exitcode")).end_with?("\tc128dcr\tc64\n")
  end

  def test_boots_a_c128_in_c64_mode
    machine = parse("", type: "exitcode").c128_machine

    assert_equal "    **** commodore 64 basic v2 ****", Testbench.screen_text(machine.ram)[1].rstrip
  end
end

class TestTestbenchC128Mode < Minitest::Test
  def parse(dir, prg, options = "")
    Testbench::C128ModeTestlist.parse("#{dir}/,#{prg},exitcode,1000,#{options}")
  end

  def test_runs_a_row_on_a_c128_in_c128_mode
    test = parse("../c128/mmu", "mmuswap-00.prg")

    assert_equal [true, :c128, "c128"], [test.c128?, test.c128_mode, test.c128_model]
  end

  def test_takes_the_rows_c128_mode_alone_runs
    %w[mmu c64modemmu ram0001 ram0001mmu vic-mmu vdccrash 2mhzVIC d030tester].each do |dir|
      refute_nil parse("../c128/#{dir}", "t.prg")
    end
    refute_nil parse("./selftest", "c128-pass.prg")
  end

  def test_drops_the_rows_that_need_the_z80_or_an_expansion
    assert_nil parse("../c128/c64modemmu", "c64modez80-00.prg")
    assert_nil parse("../c128/z80/c128z80timing", "t.prg")
    assert_nil parse("../memory-expansions", "c128-ram-emd.prg")
  end

  def test_runs_a_d71_row_with_the_drive1571
    assert_equal "1571", parse("../c128/burstmode", "burstcheck1.prg", "mountd71:burstcheck.d71").c128_drive
  end

  def test_runs_a_d64_row_with_a_drive1541
    assert_equal "1541", parse("../c128/burstmode", "burstcheck0.prg", "mountd64:burstcheck.d64").c128_drive
  end

  def test_runs_a_g71_row_with_the_drive1571
    assert_equal "1571", parse("../drive/scanner", "scanner1571-35.prg", "mountg71:scan35.g71").c128_drive
  end

  def test_drops_a_drive_row_without_a_disk
    assert_nil parse("../drive/scanner", "scanner1571-35.prg")
  end

  def test_hands_the_engine_its_drive_and_disk
    test = parse("../c128/burstmode", "burstcheck1.prg", "mountd71:burstcheck.d71")

    assert Testbench::Engine.spec(test).end_with?("\tc128\tc128\t1571\t#{test.disk_path}\n")
  end

  def test_takes_only_the_rows_that_need_the_z80_with_z80
    z80 = lambda do |dir, prg|
      Testbench::C128ModeTestlist.parse("#{dir}/,#{prg},exitcode,1000", z80: true)
    end

    assert_equal([true, true, true, false, false],
                 [z80.call("../c128/c64modemmu", "c128modez80-00.prg"),
                  z80.call("../c128/z80/c128z80timing", "00-nop.prg"),
                  z80.call("../c128/z80/zex128", "prelim.prg"),
                  z80.call("../c128/c64modemmu", "c64modemmu-00.prg"),
                  z80.call("../c128/mmu", "mmuswap-00.prg")].map { |test| !test.nil? })
  end

  def test_drops_the_c128_cartridge_rows
    assert_nil Testbench::C128ModeTestlist.parse("./selftest/,,exitcode,1000,mountcrt:c128-pass.crt")
  end

  def test_hands_the_engine_its_mode
    assert Testbench::Engine.spec(parse("../c128/mmu", "mmuswap-00.prg")).end_with?("\tc128\tc128\n")
  end

  def test_boots_a_c128_in_c128_mode
    machine = parse("../c128/mmu", "mmuswap-00.prg").c128_machine

    assert_equal " commodore basic v7.0 122365 bytes free", Testbench.screen_text(machine.ram)[1].rstrip
  end
end

class TestTestbenchExpectations < Minitest::Test
  def test_case(*options)
    Testbench::TestCase.new("../CPU/cpujam", "t.prg", "exitcode", 1000, options)
  end

  def test_success_wants_a_zero_exit_code
    assert test_case.satisfied_by?(0x00)
  end

  def test_success_rejects_a_failure_code
    refute test_case.satisfied_by?(0xff)
  end

  def test_success_rejects_a_test_that_never_reported
    refute test_case.satisfied_by?(nil)
  end

  def test_error_wants_a_nonzero_exit_code
    assert test_case("expect:error").satisfied_by?(0xff)
  end

  def test_error_rejects_a_pass
    refute test_case("expect:error").satisfied_by?(0x00)
  end

  def test_error_rejects_a_test_that_never_reported
    refute test_case("expect:error").satisfied_by?(nil)
  end

  def test_timeout_wants_no_report_at_all
    assert test_case("expect:timeout").satisfied_by?(nil)
  end

  def test_timeout_rejects_a_reported_pass
    refute test_case("expect:timeout").satisfied_by?(0x00)
  end
end

class TestTestbenchSelection < Minitest::Test
  def tests(*ids)
    ids.map { |id| Testbench::TestCase.new("../#{File.dirname(id)}", File.basename(id), "exitcode", 1000, []) }
  end

  def selected(filters, **bounds)
    IDS.select { |id| Testbench::Testlist.selected?(tests(id).first, filters, bounds[:scope], bounds[:exclude]) }
  end

  IDS = ["VICII/border/t.prg", "interrupts/irqdma/test1.prg",
         "interrupts/irqnoack/test1.prg", "CPU/cpujam/t.prg",
         "C64/bankio/t.prg", "general/banking00/t.prg"].freeze

  def test_no_filter_runs_the_whole_scope
    assert_equal ["interrupts/irqdma/test1.prg", "interrupts/irqnoack/test1.prg"],
                 selected([], scope: "interrupts/")
  end

  def test_a_scope_can_name_several_prefixes
    assert_equal ["C64/bankio/t.prg", "general/banking00/t.prg"], selected([], scope: "C64/,general/")
  end

  def test_a_filter_is_matched_inside_the_scope
    assert_equal ["interrupts/irqnoack/test1.prg"],
                 selected(["test1"], scope: "interrupts/irqnoack/")
  end

  def test_exclude_carves_a_subtree_out_of_the_scope
    assert_equal ["interrupts/irqnoack/test1.prg"],
                 selected([], scope: "interrupts/", exclude: "interrupts/irqdma/")
  end

  def test_filters_are_a_union
    assert_equal ["VICII/border/t.prg", "CPU/cpujam/t.prg"], selected(%w[border cpujam])
  end

  def test_a_bang_filter_leaves_its_tests_out_of_the_scope
    assert_equal ["interrupts/irqnoack/test1.prg"], selected(["!irqdma"], scope: "interrupts/")
  end

  def test_a_bang_filter_is_never_unmatched
    assert_empty Testbench::Testlist.unmatched(%w[border !viavarious], tests(*IDS))
  end

  def test_a_filter_outside_the_scope_selects_nothing
    assert_empty selected(["cpujam"], scope: "VICII/")
  end

  def test_a_filter_that_matched_nothing_is_reported
    assert_equal ["nope"], Testbench::Testlist.unmatched(%w[border nope], tests(*IDS))
  end

  def test_a_filter_that_matched_is_not_reported
    assert_empty Testbench::Testlist.unmatched(["border"], tests(*IDS))
  end
end

class TestTestbenchSharding < Minitest::Test
  def groups(count, shards)
    tests = Array.new(count) do |index|
      Testbench::TestCase.new("../VICII/x", "t#{index}.prg", "exitcode", (index + 1) * 1000, [])
    end
    Testbench::Shards.split(tests, [shards, count].min)
  end

  def test_every_test_is_assigned_exactly_once
    assert_equal (1..20).to_a, groups(20, 4).flatten.map { |test| test.timeout / 1000 }.sort
  end

  def test_each_shard_runs_its_tests_in_testlist_order
    groups(20, 4).each do |group|
      budgets = group.map(&:timeout)

      assert_equal budgets.sort, budgets
    end
  end

  def test_the_longest_budgets_are_spread_across_shards
    heaviest = groups(20, 4).map { |group| group.map(&:timeout).max }

    assert_equal 4, heaviest.uniq.length
  end

  def test_more_shards_than_tests_collapses_to_one_per_test
    assert_equal 3, groups(3, 8).length
  end

  def test_shard_count_falls_back_to_the_default
    assert_equal [Testbench::Runner::DEFAULT_SHARDS, Etc.nprocessors].min,
                 with_env(nil) { Testbench::Runner.shard_count(nil) }
  end

  def test_shard_count_reads_the_environment
    assert_equal 2, with_env("2") { Testbench::Runner.shard_count(nil) }
  end

  def test_an_explicit_count_wins_over_the_environment
    assert_equal 1, with_env("8") { Testbench::Runner.shard_count("1") }
  end

  def test_shard_count_is_capped_by_the_cores_available
    assert_equal Etc.nprocessors, with_env(nil) { Testbench::Runner.shard_count("999") }
  end

  private

  def with_env(value)
    previous = ENV.fetch("SHARDS", nil)
    value ? ENV["SHARDS"] = value : ENV.delete("SHARDS")
    yield
  ensure
    previous ? ENV["SHARDS"] = previous : ENV.delete("SHARDS")
  end
end

class TestTestbenchInterruption < Minitest::Test
  # Each shard reports its PID down the pipe and then hangs in its first
  # test, standing in for a long run.
  class HangingRunner < Testbench::Runner
    def initialize(tests, results_path, pipe)
      super(tests, results_path, shards: 2)
      @pipe = pipe
    end

    private

    def run_one(_test)
      @pipe.puts(Process.pid)
      @pipe.flush
      sleep 60
      "PASS"
    end
  end

  def setup
    @results = File.join(Dir.mktmpdir("interrupt"), "results.txt")
    tests = Array.new(2) { |n| Testbench::TestCase.new("../VICII/x", "t#{n}.prg", "exitcode", 1000, []) }
    reader, writer = IO.pipe
    @runner = fork { run_runner(tests, writer) }
    writer.close
    @shards = Array.new(2) { Integer(reader.gets) }
    Process.kill("TERM", @runner)
    @status = wait_briefly(@runner)
  end

  def teardown
    [@runner, *@shards].each do |pid|
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      nil
    end
    Process.wait(@runner) unless @status
    FileUtils.rm_rf(File.dirname(@results))
  end

  def test_the_runner_reports_the_interruption
    assert_equal 3, @status&.exitstatus
  end

  def test_every_shard_is_stopped_with_the_runner
    assert_empty(@shards.select { |pid| alive?(pid) })
  end

  def test_an_interrupted_run_writes_no_results
    refute_path_exists @results
  end

  private

  def run_runner(tests, pipe)
    HangingRunner.new(tests, @results, pipe).run
    exit!(0)
  rescue Testbench::Interrupted
    exit!(3)
  end

  # A runner that waits out its shards instead of stopping them would
  # still exit once they finish, so it gets a few seconds and no more.
  def wait_briefly(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status

      sleep 0.05
    end
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end

class TestTestbenchProgress < Minitest::Test
  # Scores from a table in its own process instead of forking from a
  # booted machine, and says nothing.
  class StubRunner < Testbench::Runner
    attr_reader :ran

    def initialize(scores, results_path, **)
      super(scores.keys, results_path, **)
      @scores = scores
      @ran = []
    end

    private

    def in_child(test)
      @ran << test.key
      score = @scores.fetch(test)
      score.respond_to?(:call) ? score.call : score
    end

    def report(*); end
  end

  # A kill the runner can't trap, like the one that ends a background run.
  KILL = -> { Process.kill("KILL", Process.pid) }

  def setup
    @dir = Dir.mktmpdir("progress")
    @results = File.join(@dir, "results.txt")
    @tests = Array.new(3) { |n| Testbench::TestCase.new("../VICII/x", "t#{n}.prg", "exitcode", 1000, []) }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_finished_run_writes_its_rows_in_testlist_order
    run_stub(shards: 2)

    assert_equal "VICII/x/t0.prg\tPASS\nVICII/x/t1.prg\tFAIL\texit=$ff\nVICII/x/t2.prg\tPASS\n",
                 File.read(@results)
  end

  def test_a_finished_run_clears_its_progress
    run_stub

    refute_path_exists progress
  end

  def test_resume_skips_the_rows_already_finished
    File.write(progress, "VICII/x/t0.prg\tFAIL\texit=none\n")

    assert_equal ["VICII/x/t1.prg", "VICII/x/t2.prg"], run_stub(resume: true).ran
  end

  def test_resumed_rows_keep_their_verdict
    File.write(progress, "VICII/x/t0.prg\tFAIL\texit=none\n")
    run_stub(resume: true)

    assert_equal "VICII/x/t0.prg\tFAIL\texit=none\n", File.readlines(@results).first
  end

  def test_a_run_without_resume_starts_over
    File.write(progress, "VICII/x/t0.prg\tPASS\n")

    assert_equal 3, run_stub.ran.length
  end

  def test_a_row_cut_short_is_run_again
    File.write(progress, "VICII/x/t0.prg\tPASS\nVICII/x/t1.prg\tPA")

    assert_equal ["VICII/x/t1.prg", "VICII/x/t2.prg"], run_stub(resume: true).ran
  end

  def test_a_killed_run_keeps_the_rows_it_finished
    Process.wait(fork { run_stub(overrides: { @tests[1] => KILL }) })

    assert_equal "VICII/x/t0.prg\tPASS\n", File.read(progress)
  end

  def test_a_killed_run_writes_no_results
    Process.wait(fork { run_stub(overrides: { @tests[1] => KILL }) })

    refute_path_exists @results
  end

  def test_a_repeated_id_is_keyed_by_its_occurrence
    tests = Testbench::Testlist.numbered(Array.new(2) { @tests.first.dup })

    assert_equal ["VICII/x/t0.prg", "VICII/x/t0.prg#2"], tests.map(&:key)
  end

  def test_a_repeated_id_gets_a_results_row_of_its_own
    @tests = Testbench::Testlist.numbered([@tests[0], @tests[0].dup, @tests[2]])
    run_stub
    keys = File.readlines(@results).map { |line| line.split("\t").first }

    assert_equal ["VICII/x/t0.prg", "VICII/x/t0.prg#2", "VICII/x/t2.prg"], keys
  end

  def test_each_vicii_counts_its_own_occurrences
    old, new = %w[vicii-old vicii-new].map do |option|
      Testbench::TestCase.new("../VICII/x", "t.prg", "screenshot", 1000, [option])
    end
    tests = Testbench::Testlist.numbered([new, old])

    assert_equal ["VICII/x/t.prg", "VICII/x/t.prg"], tests.map(&:key)
  end

  def test_each_cia_counts_its_own_occurrences
    old, new = %w[cia-old cia-new].map do |option|
      Testbench::TestCase.new("../CIA/x", "t.prg", "exitcode", 1000, [option])
    end
    tests = Testbench::Testlist.numbered([new, old])

    assert_equal ["CIA/x/t.prg", "CIA/x/t.prg"], tests.map(&:key)
  end

  private

  def progress
    "#{@results}.progress"
  end

  def run_stub(shards: 1, resume: false, overrides: {})
    scores = @tests.zip(["PASS", "exit=$ff", "PASS"]).to_h.merge(overrides)
    StubRunner.new(scores, @results, shards:, resume:).tap { |runner| capture_io { runner.run } }
  end
end

class TestTestbenchEngine < Minitest::Test
  # Stands in for a Spinel build of spinel/testbench.rb: a test whose key
  # says so crashes the build, hangs it or fails, and the rest pass.
  BUILD = <<~RUBY
    #!/usr/bin/env ruby
    File.readlines(ARGV[0]).each do |line|
      key, type = line.split("\\t")
      exit 3 if key.include?("crash")
      sleep 30 if key.include?("hang")
      puts "test \#{key}", "exit \#{key.include?('fail') ? 255 : 0}", "cycles 1"
      if type == "exitcode"
        puts "text", *Array.new(25) { "ready." }
      else
        puts "screen", *Array.new(272) { "0e" * 192 }
      end
      puts "done"
      $stdout.flush
    end
  RUBY

  Test = Struct.new(:key, :type, :deadline) do
    def budget = 1000
    def cartridge = nil
    def prg = "#{key}.prg"
    def dir_abs = "/tests"
    def cia_model = :mos6526
    def vic_model = :mos6569
    def expansion = nil
    def region = :pal
    def drive? = false
    def disk = nil
    def load_name = ""
    def vic20? = false
    def c128? = false
  end

  def setup
    @dir = Dir.mktmpdir("engine")
    @build = File.join(@dir, "build")
    File.write(@build, BUILD)
    File.chmod(0o755, @build)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_test_is_a_line_of_tab_separated_fields
    test = Testbench::TestCase.new("../VICII/x", "t.prg", "exitcode", 1000, [])

    assert_equal "VICII/x/t.prg\texitcode\t3001000\t\tt.prg\t#{test.dir_abs}\tmos6526\tmos6569\t\tpal\t\t\t\n",
                 Testbench::Engine.spec(test)
  end

  def test_a_test_line_ends_with_the_expansion
    test = Testbench::TestCase.new("../plus60k", "t.prg", "exitcode", 1000, ["plus60k"])

    assert Testbench::Engine.spec(test).end_with?("\tmos6526\tmos6569\tplus60k\tpal\t\t\t\n")
  end

  def test_a_screenshot_reads_as_rows_of_palette_indices
    outcome = Testbench::Engine.parse(record("screen", "0e" * 192), Test.new("t", "screenshot"))

    assert_equal [0, 14], outcome.screen.first.first(2)
  end

  def test_a_screenshot_keeps_only_its_own_rows
    outcome = Testbench::Engine.parse(record("screen", "0e" * 192), Test.new("t", "screenshot"))

    assert_equal 272, outcome.screen.length
  end

  def test_a_test_that_never_reported_has_no_exit_code
    assert_nil Testbench::Engine.parse(record("text", "ready."), Test.new("t", "exitcode")).exit_code
  end

  def test_a_record_for_another_test_is_refused
    assert_raises(ArgumentError) { Testbench::Engine.parse(record("text", "ready."), Test.new("u", "exitcode")) }
  end

  def test_each_test_gets_its_exit_code
    assert_equal [0, 255], run_engine(%w[pass fail])
  end

  def test_a_crash_fails_its_test_and_the_rest_run_on
    assert_equal ["crashed: exit 3", 0], run_engine(%w[crash pass])
  end

  def test_a_hung_test_is_killed_and_the_rest_run_on
    assert_equal ["hung: killed after 1s", 0], run_engine(%w[hang pass], deadline: 0.5)
  end

  def test_an_engine_run_writes_the_rows_bin_testbench_would
    tests = %w[pass crash].map { |name| Testbench::TestCase.new("../VICII/x", "#{name}.prg", "exitcode", 1000, []) }
    results = File.join(@dir, "results.txt")
    capture_io { Testbench::Runner.new(tests, results, shards: 2, engine: @build).run }

    assert_equal "VICII/x/pass.prg\tPASS\nVICII/x/crash.prg\tFAIL\tcrashed: exit 3\n", File.read(results)
  end

  private

  def record(kind, row)
    rows = Array.new(kind == "screen" ? 272 : 25, row)
    ["test t", "exit none", "cycles 1", kind, *rows, "done"].join("\n") << "\n"
  end

  # The exit code each test reported, or how it failed to.
  def run_engine(keys, deadline: 10)
    engine = Testbench::Engine.new(@build, File.join(@dir, "list"), spawned: ->(_) {}, stopped: -> {})
    results = []
    engine.run(keys.map { |key| Test.new(key, "exitcode", deadline) }) do |_, outcome|
      results << (outcome.is_a?(String) ? outcome : outcome.exit_code)
    end
    results
  end
end
