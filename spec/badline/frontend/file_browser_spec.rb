# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::FileBrowser do
  subject(:browser) { described_class.new(nil, nil) }

  let(:dir) { File.realpath(Dir.mktmpdir) }

  before do
    FileUtils.mkdir_p(File.join(dir, "games/sub"))
    %w[disk10.d64 disk2.d64 readme.txt .hidden.d64 games/one.d64].each { |name| FileUtils.touch(File.join(dir, name)) }
    browser.open(dir, %w[.d64])
  end

  after { FileUtils.remove_entry(dir) }

  def keys(*scancodes) = scancodes.map { |scancode| browser.key(scancode) }.last

  it "lists the parent and the folders first, then the files it takes, numbers in order" do
    expect(keys(81, 81, 81, 40)).to eq(File.join(dir, "disk10.d64"))
  end

  it "leaves out hidden files and those it doesn't take" do
    expect(keys(77, 40)).to eq(File.join(dir, "disk10.d64"))
  end

  it "picks a file with Return" do
    expect(keys(81, 81, 40)).to eq(File.join(dir, "disk2.d64"))
  end

  it "goes into a folder with Return" do
    keys(81, 40)
    expect(browser.directory).to eq(File.join(dir, "games"))
  end

  it "goes up with Left, back to the folder it came from" do
    keys(81, 40, 80, 40)
    expect(browser.directory).to eq(File.join(dir, "games"))
  end

  it "jumps to the next name starting with a letter" do
    expect(keys(7, 40)).to eq(File.join(dir, "disk2.d64"))
  end

  it "cancels with Esc" do
    expect(keys(41)).to eq(:cancel)
  end
end
