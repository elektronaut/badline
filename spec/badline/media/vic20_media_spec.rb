# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Media::Vic20Media do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:ram) { Badline::Memory.new(length: 0xc000) }
  let(:basic_start) { 0x1201 }
  let(:machine) do
    instance_double(Badline::Vic20, ram:, basic_start:, type_text: nil, load_prg: nil, attach_cartridge: nil,
                                    mount: nil).tap { |double| allow(double).to receive(:on_init).and_yield }
  end

  after { FileUtils.remove_entry(dir) }

  # A program file of +bytes+ loading at +address+.
  def program(name, address, bytes = [0x00])
    File.join(dir, name).tap { |path| File.binwrite(path, [address & 0xff, address >> 8, *bytes].pack("C*")) }
  end

  # A BASIC program of two lines, 10 and 20, saved from +address+, its
  # links pointing where they did there.
  def basic_program(address)
    second = address + 7
    finish = address + 13
    program("basic.prg", address,
            [second & 0xff, second >> 8, 10, 0, 0x99, 0x31, 0, finish & 0xff, finish >> 8, 20, 0, 0x80, 0, 0, 0])
  end

  def attach(path, autostart: true) = Badline::Media.attach(machine, path, autostart:)

  describe ".ram_for" do
    subject { Badline::Media.vic20_ram_for(path) }

    {
      [0x1001, 100] => :unexpanded, [0x0401, 100] => :"3k", [0x1201, 100] => :"8k", [0x1201, 0x3000] => :"16k",
      [0x1201, 0x7000] => :"24k", [0x2000, 0x100] => :"8k", [0x6000, 0x100] => :"24k", [0x1c00, 10] => :unexpanded,
      [0xa000, 0x100] => :unexpanded
    }.each do |(address, length), expected|
      context "with a program of #{length} bytes at $#{address.to_s(16)}" do
        let(:path) { program("game.prg", address, Array.new(length, 0)) }

        it { is_expected.to eq(expected) }
      end
    end

    context "with a directory" do
      let(:path) { dir.tap { program("first.prg", 0x1201) } }

      it { is_expected.to eq(:"8k") }
    end

    context "with a disk image" do
      let(:path) { blank_d64(File.join(dir, "disk.d64")) }

      before { Badline::Storage::D64Image.new(path).write_file("GAME", [0x01, 0x04, 0x00]) }

      it { is_expected.to eq(:"3k") }
    end

    context "with a cartridge image" do
      let(:path) { File.join(dir, "game.crt") }

      it { is_expected.to eq(:unexpanded) }
    end
  end

  describe ".attach" do
    context "with a BASIC program saved at the machine's start of BASIC" do
      before { attach(basic_program(0x1201)) }

      it "loads it there" do
        expect(ram.read(0x1201, 4)).to eq([0x08, 0x12, 10, 0])
      end

      it "sets the end of the program and the end address" do
        expect([ram.peek16(0x2d), ram.peek16(0xae)]).to eq([0x1210, 0x1210])
      end

      it "runs it" do
        expect(machine).to have_received(:type_text).with("run\r")
      end
    end

    context "with a BASIC program saved at another start of BASIC" do
      before { attach(basic_program(0x1001)) }

      it "relinks its lines at the machine's start of BASIC" do
        expect([ram.peek16(0x1201), ram.peek16(0x1208)]).to eq([0x1208, 0x120e])
      end
    end

    context "without autostart" do
      before { attach(basic_program(0x1201), autostart: false) }

      it "doesn't run it" do
        expect(machine).not_to have_received(:type_text)
      end
    end

    context "with a machine-language program" do
      before { attach(program("ml.prg", 0x1c00, [0xa9])) }

      it "loads it where it says" do
        expect(machine).to have_received(:load_prg).with([0x00, 0x1c, 0xa9])
      end
    end

    context "with a program at $A000" do
      before { attach(program("game.prg", 0xa000, [0x01, 0x02])) }

      it "puts it in as a cartridge's ROM, padded to a page" do
        expect(machine).to have_received(:attach_cartridge)
          .with([have_attributes(address: 0xa000, data: [0x01, 0x02] + ([0xff] * 254))])
      end
    end

    context "with the $6000 part of a set named by block" do
      before do
        program("game-a000.prg", 0xa000)
        attach(program("game-6000.prg", 0x6000))
      end

      it "puts in both parts" do
        expect(machine).to have_received(:attach_cartridge)
          .with([have_attributes(address: 0xa000), have_attributes(address: 0x6000)])
      end
    end

    context "with a set named by extension" do
      before do
        program("GAME.60", 0x6000)
        attach(program("GAME.A0", 0xa000))
      end

      it "puts in both parts" do
        expect(machine).to have_received(:attach_cartridge)
          .with([have_attributes(address: 0xa000), have_attributes(address: 0x6000)])
      end
    end

    context "with a $6000 program and no $A000 part" do
      before { attach(program("game-6000.prg", 0x6000)) }

      it "loads it into RAM" do
        expect(machine).to have_received(:load_prg)
      end
    end

    context "with a VIC-20 .crt" do
      let(:path) do
        File.join(dir, "game.crt").tap do |crt|
          header = "VIC20 CARTRIDGE ".b + [0x40, 0x0100, 0, 0, 0, 0].pack("NnnCCCx5") + ("\x00" * 32)
          File.binwrite(crt, header + ["CHIP", 0x110, 0, 0, 0xa000, 0x100].pack("a4Nn4") + ("\x01" * 0x100))
        end
      end

      before { attach(path) }

      it "puts its chips in" do
        expect(machine).to have_received(:attach_cartridge).with([have_attributes(address: 0xa000)])
      end
    end

    context "with a disk image whose first program is BASIC" do
      let(:path) { blank_d64(File.join(dir, "disk.d64")) }

      before do
        Badline::Storage::D64Image.new(path).write_file("GAME", [0x01, 0x10, 0x00])
        attach(path)
      end

      it "loads it relocated and runs it" do
        expect(machine).to have_received(:type_text).with(%(lO"*",8\rrun\r))
      end
    end

    context "with a disk image whose first program isn't BASIC" do
      let(:path) { blank_d64(File.join(dir, "disk.d64")) }

      before do
        Badline::Storage::D64Image.new(path).write_file("GAME", [0x00, 0x1c, 0x00])
        attach(path)
      end

      it "loads it where it says and runs it" do
        expect(machine).to have_received(:type_text).with(%(lO"*",8,1\rrun\r))
      end
    end

    context "with a directory" do
      it "mounts it as device 8" do
        attach(dir)
        expect(machine).to have_received(:mount).with(instance_of(Badline::Storage::HostDirectory))
      end
    end

    context "with a tape" do
      it "refuses it" do
        expect { attach(File.join(dir, "game.tap")) }.to raise_error(ArgumentError, /VIC-20/)
      end
    end
  end
end
