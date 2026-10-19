# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media::KIM1Media do
  let(:dir) { Dir.mktmpdir }
  let(:tty) { false }
  let(:ram) { :"1k" }

  # A KIM-1 that runs what waits for the boot at once.
  let(:kim) do
    Badline::KIM1.new(tty:, ram:).tap do |kim|
      allow(kim).to receive(:on_init).and_yield
      allow(kim).to receive(:type_text)
    end
  end

  after { FileUtils.remove_entry(dir) }

  # INC $10, then a JMP back to it, at $0200.
  def program = [0xe6, 0x10, 0x4c, 0x00, 0x02]

  # The program, and a byte at $17E0.
  def papertape = write("inc.ptp", tape([0x0200, program], [0x17e0, [0x5a]]))

  def record(address, bytes)
    fields = [bytes.size, address >> 8, address & 0xff] + bytes
    sum = fields.sum
    ";#{(fields + [sum >> 8, sum & 0xff]).map { |byte| format('%02X', byte) }.join}\n"
  end

  def tape(*records) = records.map { |address, bytes| record(address, bytes) }.join + record(records.size, [])

  def write(name, text) = File.join(dir, name).tap { |path| File.binwrite(path, text) }

  def attach(path, autostart: true, **loading)
    Badline::Media.attach(kim, path, autostart:, kim1: described_class::Loading.new(**loading))
  end

  def bytes_at(address, count) = Array.new(count) { |offset| kim.peek(address + offset) }

  describe "a papertape" do
    it "goes in at its records' addresses" do
      attach(papertape)
      expect([bytes_at(0x0200, 5), kim.peek(0x17e0)]).to eq([program, 0x5a])
    end

    it "points the NMI and IRQ vectors at the monitor" do
      attach(papertape)
      expect(bytes_at(0x17fa, 6)).to eq([0x00, 0x1c, 0x00, 0x00, 0x00, 0x1c])
    end

    it "says where it loads" do
      path = papertape
      expect(attach(path)).to eq("Loading #{path} at $0200")
    end

    it "starts from where it loads on the keypad" do
      attach(papertape)
      expect(kim).to have_received(:type_text).with("AD 0 2 0 0 GO")
    end

    it "stops at the start address without autostart" do
      attach(papertape, autostart: false, start_address: 0x0123)
      expect(kim).to have_received(:type_text).with("AD 0 1 2 3")
    end

    context "with the TTY/KB jumper fitted" do
      let(:tty) { true }

      it "starts on the teletype" do
        attach(papertape)
        expect(kim).to have_received(:type_text).with("0200 G")
      end

      it "goes in through the L command when the teletype loads it" do
        attach(papertape, teletype: true)
        expect([kim.teletype.busy?, kim.peek(0x0200)]).to eq([true, 0x00])
      end
    end

    it "refuses one outside the RAM" do
      path = write("high.ptp", tape([0x0400, [0xea]]))
      expect { attach(path) }.to raise_error(Badline::Machine::Unsupported, /\$0400-\$0400.*--ram 5k/)
    end

    context "with 5K" do
      let(:ram) { :"5k" }

      it "goes in at $0400" do
        attach(write("high.ptp", tape([0x0400, [0xea]])))
        expect(kim.peek(0x0400)).to eq(0xea)
      end
    end
  end

  describe "a .bin" do
    def binary = write("inc.bin", program.pack("C*"))

    it "goes in at $0200" do
      attach(binary)
      expect(bytes_at(0x0200, 5)).to eq(program)
    end

    it "goes in at its load address" do
      attach(binary, load_address: 0x0300)
      expect(bytes_at(0x0300, 5)).to eq(program)
    end

    it "refuses an empty one" do
      expect { attach(write("empty.bin", "")) }.to raise_error(Badline::Machine::Unsupported, /no bytes/)
    end
  end

  it "refuses a .prg" do
    expect { attach(write("game.prg", "\x01\x08")) }.to raise_error(Badline::Machine::Unsupported)
  end

  it "takes the command line's addresses" do
    options = Badline::Options.parse(["kim1", "--load-address", "$0300", "--start-address", "0305", binary_path])
    loading = described_class.loading(options)
    expect([loading.load_address, loading.start_address, loading.teletype?]).to eq([0x0300, 0x0305, false])
  end

  def binary_path = write("game.bin", "\xea")

  describe "a program that runs", :slow do
    let(:kim) { Badline::KIM1.new(tty:) }

    it "counts at $10 once the monitor has started it" do
      attach(papertape)
      kim.run_cycles(200_000)
      expect([kim.peek(0x10).positive?, (0x0200..0x0204).cover?(kim.cpu.program_counter)]).to eq([true, true])
    end

    context "when the teletype loads it" do
      let(:tty) { true }

      it "runs it once the monitor's L command has read it" do
        attach(papertape, teletype: true)
        kim.run_cycles(400_000)
        expect([bytes_at(0x0200, 5), kim.peek(0x10).positive?]).to eq([program, true])
      end
    end
  end
end
