# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/blank_disk"

describe Badline::Frontend::MenuDialogs do
  include BlankDisk

  subject(:dialogs) { described_class.new(painter, buttons, media, Badline::Options.parse([])) }

  let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, box: nil) }
  let(:buttons) { Badline::Frontend::Buttons.new(painter, [1, 2, 3, 4]) }
  let(:media) { Badline::Frontend::MenuMedia.new("", false).tap { |menu_media| menu_media.computer = Badline::Computer.new } }
  let(:dir) { Dir.mktmpdir }
  let(:crt_path) do
    File.join(dir, "game.crt").tap do |path|
      header = "C64 CARTRIDGE   ".b + [0x40, 0x0100, 0, 0, 1].pack("NnnCC") + ("\x00" * 6) + "GAME".ljust(32, "\x00")
      File.binwrite(path, header + "CHIP".b + [0x2010, 0, 0, 0x8000, 0x2000].pack("Nn4") + ("\x42" * 0x2000))
    end
  end

  after { FileUtils.remove_entry(dir) }

  # Presses the keys, laying the question out before each, as the menu's
  # frames do.
  def press(*scancodes) = scancodes.map { |scancode| dialogs.draw(0, 0, 300).then { dialogs.key(scancode) } }.last

  it "puts a dropped disk straight in" do
    expect([dialogs.drop(blank_d64(File.join(dir, "game.d64"))), media.inserted?]).to eq([false, true])
  end

  it "asks before a dropped cartridge goes in" do
    expect([dialogs.drop(crt_path), dialogs.open?]).to eq([true, true])
  end

  it "leaves other dropped files alone" do
    expect(dialogs.drop(File.join(dir, "notes.txt"))).to be(false)
  end

  it "cancels with Return, CANCEL having the focus" do
    dialogs.drop(crt_path)
    expect([press(40), media.cartridge_name]).to eq([nil, ""])
  end

  it "puts the cartridge in once its answer is pressed, and resumes" do
    dialogs.drop(crt_path)
    expect([press(81, 40), media.cartridge_name]).to eq([:resume, "GAME"])
  end

  it "goes back to the menu with Esc" do
    dialogs.drop(crt_path)
    press(41)
    expect(dialogs.open?).to be(false)
  end
end
