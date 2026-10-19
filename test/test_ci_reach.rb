# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/ci_matrix"

class TestCIReach < Minitest::Test
  def test_every_rule_names_known_suites
    known = Suites::ALL_SUITES.keys + CIMatrix::CHECKS.keys
    named = CIReach::RULES.map(&:last).grep(Array).flatten.uniq

    assert_empty named - known, "CIReach names #{(named - known).join(', ')}, which no suite or check is"
  end

  def test_a_path_no_rule_names_reaches_everything
    assert_equal CIReach::ALL, CIReach.suites(%w[lib/badline/kernal_trap/load.rb])
  end

  def test_specs_reach_nothing
    assert_empty CIReach.suites(%w[spec/badline/chips/cia_spec.rb])
  end

  def test_a_lib_change_runs_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/frontend/controls.rb])
  end

  def test_a_units_snapshot_fields_reach_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/chips/cia/keyed_parts.rb])
  end

  def test_the_vics_sprite_fields_reach_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/chips/vic/keyed_sprites.rb])
  end

  def test_a_machines_snapshot_modules_reach_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/c128/keyed_modules.rb])
  end

  def test_the_6809_vector_runner_reaches_no_suite
    assert_empty CIReach.suites(%w[test/support/moo_reader.rb test/support/m6809_vectors.rb])
  end

  def test_the_6809_reaches_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/chips/m6809.rb lib/badline/chips/m6809/core.rb])
  end

  def test_the_rom_readme_reaches_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/roms/README])
  end

  def test_the_superpets_roms_reach_only_the_spinel_check
    files = %w[lib/badline/roms/pet/superpet-a000.rom lib/badline/roms/pet/characters-superpet.rom]

    assert_equal %w[spinel:check], CIReach.suites(files)
  end

  def test_the_cbm2_its_roms_tpi_and_testlist_reach_its_testbench
    files = %w[lib/badline/cbm2/model.rb lib/badline/cbm2/bus.rb lib/badline/roms/cbm2/kernal-04a.rom
               lib/badline/chips/tpi.rb test/support/testbench_cbm2_machine.rb]

    assert_equal %w[spinel:check testbench-cbm2 testbench-cbm5x0], CIReach.suites(files)
  end

  def test_the_p500_its_roms_and_harnesses_reach_its_testbench_alone
    files = %w[lib/badline/cbm2/p500/pages.rb lib/badline/cbm2/p500/model.rb lib/badline/roms/cbm2/p500-kernal.rom
               test/support/testbench_p500_machine.rb spinel/p500_testbench.rb]

    assert_equal %w[spinel:check testbench-cbm5x0], CIReach.suites(files)
  end

  def test_the_kim1_and_its_roms_reach_only_the_spinel_check
    files = %w[lib/badline/kim1.rb lib/badline/kim1/bus.rb lib/badline/roms/kim1/6530-002.rom]

    assert_equal %w[spinel:check], CIReach.suites(files)
  end

  def test_the_vic_reaches_the_p500s_testbench
    assert_includes CIReach.suites(%w[lib/badline/chips/vic/bank.rb]), "testbench-cbm5x0"
  end

  def test_the_shared_ieee_drives_reach_the_pet_and_the_cbm2
    assert_equal %w[drive-scenarios spinel:check testbench-cbm2 testbench-cbm5x0 testbench-pet
                    testbench-pet-discrete],
                 CIReach.suites(%w[lib/badline/machine/ieee_drives.rb lib/badline/drives/ieee_models.rb])
  end

  def test_the_cbm2_and_its_ieee_ports_reach_the_drive_scenarios_too
    files = %w[lib/badline/cbm2.rb lib/badline/cbm2/ieee_ports.rb lib/badline/cbm2/ieee_drive.rb]

    assert_equal %w[drive-scenarios spinel:check testbench-cbm2 testbench-cbm5x0], CIReach.suites(files)
  end

  def test_the_p500_and_its_control_ports_reach_the_drive_scenarios_too
    files = %w[lib/badline/cbm2/p500.rb lib/badline/cbm2/p500/control_ports.rb]

    assert_equal %w[drive-scenarios spinel:check testbench-cbm5x0], CIReach.suites(files)
  end

  def test_the_chips_the_cbm2_shares_reach_its_testbench
    files = %w[lib/badline/chips/cia.rb lib/badline/chips/sid.rb lib/badline/chips/acia.rb lib/badline/chips/crtc.rb]

    assert_includes CIReach.suites(files), "testbench-cbm2"
  end

  def test_the_chips_the_p500_shares_reach_its_testbench
    files = %w[lib/badline/chips/cia.rb lib/badline/chips/sid.rb lib/badline/chips/acia.rb lib/badline/chips/tpi.rb]

    assert_includes CIReach.suites(files), "testbench-cbm5x0"
  end

  def test_the_crtc_leaves_the_p500_alone
    refute_includes CIReach.suites(%w[lib/badline/chips/crtc.rb]), "testbench-cbm5x0"
  end

  def test_the_8050_and_its_roms_reach_the_drive_scenarios
    files = %w[lib/badline/roms/8050/fdc-901869-01.rom lib/badline/roms/1001/fdc-251257-02a.rom
               lib/badline/roms/4040/dos-2.1.rom lib/badline/drives/model8050.rb lib/badline/drives/model1001.rb
               lib/badline/chips/riot.rb
               lib/badline/chips/rriot.rb]

    assert_equal %w[drive-scenarios spinel:check], CIReach.suites(files)
  end

  def test_the_hard_disk_reaches_the_drive_scenarios
    files = %w[lib/badline/storage/d90_image.rb lib/badline/drives/model9060/sasi_target.rb]

    assert_equal %w[drive-scenarios spinel:check], CIReach.suites(files)
  end

  def test_the_pet_and_its_roms_reach_the_pet_testbenches
    files = %w[lib/badline/pet/bus.rb lib/badline/chips/pia.rb lib/badline/chips/crtc.rb
               lib/badline/roms/pet/kernal4.rom]

    assert_equal %w[spinel:check testbench-cbm2 testbench-pet testbench-pet-discrete], CIReach.suites(files)
  end

  def test_the_ieee_traps_reach_the_cbm2s_testbench_too
    assert_includes CIReach.suites(%w[lib/badline/kernal_trap/ieee.rb]), "testbench-cbm2"
  end

  def test_the_2031_and_the_pets_bus_reach_the_drive_scenarios_too
    files = %w[lib/badline/pet.rb lib/badline/pet/ieee_ports.rb lib/badline/drives/model2031/ieee_port.rb
               lib/badline/drives/ieee_bus.rb lib/badline/roms/dos2031.rom]

    assert_equal %w[drive-scenarios spinel:check testbench-pet testbench-pet-discrete], CIReach.suites(files)
  end

  def test_the_drive_scenarios_runner_reaches_only_the_drive_scenarios
    files = %w[bin/drive_scenarios test/support/drive_scenarios_runner.rb test/support/drive_scenarios_pet.rb]

    assert_equal %w[drive-scenarios drive-scenarios-cpm], CIReach.suites(files)
  end

  def test_the_via_reaches_the_pet_testbenches
    assert_empty %w[testbench-pet testbench-pet-discrete] - CIReach.suites(%w[lib/badline/chips/via.rb])
  end

  def test_input_reaches_a_suite_of_every_family
    reached = CIReach.suites(%w[lib/badline/input/keyboard.rb lib/badline/input.rb])

    assert_empty %w[lorenz testbench-vic20 testbench-c128 testbench-plus4 testbench-pet sid] - reached
  end

  def test_media_reaches_the_suites_that_attach_through_it
    reached = CIReach.suites(%w[lib/badline/media.rb lib/badline/media/plus4_media.rb])

    assert_empty %w[testbench testbench-drive testbench-c128 sid drive-scenarios spinel:check_sid] - reached
  end

  def test_media_leaves_the_suites_that_load_without_it
    reached = CIReach.suites(%w[lib/badline/media.rb])

    assert_empty %w[lorenz lorenz-plus4 testbench-vic20 testbench-plus4] & reached
  end

  def test_the_cpu_reaches_everything
    assert_equal CIReach::ALL, CIReach.suites(%w[lib/badline/chips/cpu/core.rb spec/badline/cpu_spec.rb])
  end

  def test_the_sid_reaches_the_sid_suites
    assert_equal %w[sid sid-8580 spinel:check spinel:check_sid testbench-cbm2 testbench-cbm5x0],
                 CIReach.suites(%w[lib/badline/chips/sid/voice.rb])
  end

  def test_a_baseline_reaches_its_suite
    assert_equal %w[testbench-cia], CIReach.suites(%w[test/baselines/testbench-cia.txt])
  end

  def test_the_matrix_keeps_only_reached_entries
    tasks = CIMatrix.matrix(%w[sid spinel:check]).to_h { |shard| [shard["shard"], shard["tasks"]] }

    assert_equal({ "sid-ntsc" => "spinel:sidtests[6581] spinel:check" }, tasks)
  end

  def test_the_matrix_is_empty_when_nothing_is_reached
    assert_empty CIMatrix.matrix([])
  end
end
