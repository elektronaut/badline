# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::VIC, "#save_state" do
  include SnapshotScenarios

  # The VIC's view of memory is its machine's, and each VIC builds its own
  # frozen layout tables for its region.
  let(:wiring) do
    { "Badline::VIC" => %i[@address_bus @sprite_ba_tail @sprite_ba_head @hook_columns @blank_columns @blank_lines],
      "Badline::VIC::Bank" => %i[@address_bus], "Badline::VIC::Sequencer" => %i[@window_compares] }
  end

  %i[mos6569 mos8565].each do |model|
    context "with a #{model} mid-line, sprites on" do
      let(:computer) { run(demo_machine(vic_model: model), 30_001) }
      let(:target) { demo_machine(vic_model: model) }

      # The target's memory and CPU made the saved machine's, so the two
      # VICs read the same bytes.
      def share_memory
        round_trip(computer.ram, target.ram)
        round_trip(computer.address_bus.color_ram, target.address_bus.color_ram)
        target.cpu.program_counter = computer.cpu.program_counter
      end

      def run_vics(cycles)
        cycles.times do
          computer.vic.cycle!
          target.vic.cycle!
        end
      end

      before do
        share_memory
        round_trip(computer.vic, target.vic)
      end

      it "restores every part of the VIC" do
        expect(state_differences(computer.vic, target.vic, host: wiring)).to be_empty
      end

      it "runs on as the saved VIC does" do
        run_vics(5_000)
        vic = ->(machine) { [machine.vic.register_file, machine.vic.display, machine.vic.rasterline] }
        expect(vic.call(target)).to eq(vic.call(computer))
      end

      it "leaves nothing apart once both have run on", :slow do
        run_vics(5_000)
        expect(state_differences(computer.vic, target.vic, host: wiring)).to be_empty
      end
    end
  end

  it "keeps a VIC-IIe's $D02F and $D030" do
    vic = described_class.new(model: :mos8566)
    vic.poke(0xd02f, 0x02)
    vic.poke(0xd030, 0x01)
    target = round_trip(vic, described_class.new(model: :mos8566))
    expect([target.peek(0xd02f), target.peek(0xd030)]).to eq([0xfa, 0xfd])
  end

  it "marks every line dirty for the front end" do
    computer = demo_machine
    target = demo_machine
    target.vic.clear_dirty_lines!
    round_trip(computer.vic, target.vic)
    expect(target.vic.dirty_lines).to all(be(true))
  end
end
