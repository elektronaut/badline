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

  def test_the_rom_readme_reaches_only_the_spinel_check
    assert_equal %w[spinel:check], CIReach.suites(%w[lib/badline/roms/README])
  end

  def test_the_pet_and_its_roms_reach_the_pet_testbenches
    files = %w[lib/badline/pet.rb lib/badline/pet/bus.rb lib/badline/chips/pia.rb lib/badline/chips/crtc.rb
               lib/badline/roms/pet/kernal4.rom]

    assert_equal %w[spinel:check testbench-pet testbench-pet-discrete], CIReach.suites(files)
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
    assert_equal %w[sid sid-8580 spinel:check spinel:check_sid], CIReach.suites(%w[lib/badline/chips/sid/voice.rb])
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
