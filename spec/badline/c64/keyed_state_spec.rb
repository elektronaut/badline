# frozen_string_literal: true

require "spec_helper"

# Each family's own fields and setup in a keyed snapshot module, round
# tripped into a machine built from the setup they name.
describe Badline::C64::KeyedState do
  def read(out) = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-MACHINE"))

  def glue(machine, names) = names.map { |name| machine.instance_variable_get(name) }

  context "with a C64" do
    let(:machine) do
      Badline::C64.new(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580, region: Badline::Region::NTSC,
                       ram_expansion: :plus256k, reu: 512, board: :pet64).tap do |c64|
        c64.type_text("print 6*7\r")
        c64.run_cycles(2_000)
      end
    end
    let(:out) { Badline::Snapshot::Keyed::Writer.new.tap { |writer| machine.save_machine_fields(writer) } }
    let(:fresh) { Badline::Snapshot::C64Setup.read_fields(read(out)).build }
    let(:names) { %i[@cycles @nmi_asserted @cartridge_nmi @restore_pulse @freezing @freeze_writes @dma @pending_keys] }

    it "names the setup it was built with" do
      expect(Badline::Snapshot::C64Setup.read_fields(read(out))).to eq(Badline::Snapshot::C64Setup.of(machine.address_bus))
    end

    it "restores the cycle count, the NMI glue and the keys still to type" do
      fresh.load_machine_fields(read(out))
      expect(glue(fresh, names)).to eq(glue(machine, names))
    end

    it "writes the family and the version" do
      expect([read(out).text("family", ""), read(out).text("written_by", "")]).to eq(["c64", Badline::VERSION])
    end
  end

  context "with a VIC-20" do
    let(:machine) { Badline::Vic20.new(ram: :"8k").tap { |vic20| vic20.run_cycles(2_000) } }
    let(:out) { Badline::Snapshot::Keyed::Writer.new.tap { |writer| machine.save_machine_fields(writer) } }
    let(:fresh) { Badline::Snapshot::Vic20Setup.read_fields(read(out)).build }

    it "restores the RAM expansion and the cycle count" do
      fresh.load_machine_fields(read(out))
      expect([fresh.ram_configuration, fresh.cycles]).to eq([:"8k", machine.cycles])
    end
  end

  context "with a C128 while the Z80 runs" do
    let(:machine) { Badline::C128.new(model: "c128dcr", mode: :c128).tap { |c128| c128.run_cycles(500) } }
    let(:out) { Badline::Snapshot::Keyed::Writer.new.tap { |writer| machine.save_machine_fields(writer) } }
    let(:fresh) { Badline::Snapshot::C128Setup.read_fields(read(out)).build }
    let(:names) { %i[@cycles @clock_bits @nmi_asserted @chips_ahead @cpu_reset_pending] }

    before do
      fresh.z80.instance_variable_set(:@cycles, machine.z80.cycles)
      fresh.load_machine_fields(read(out))
    end

    it "restores the model, the glue and when the Z80 is due" do
      expect([fresh.model.name, *glue(fresh, names), fresh.instance_variable_get(:@z80_due)])
        .to eq(["c128dcr", *glue(machine, names), machine.instance_variable_get(:@z80_due)])
    end
  end
end
