# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"

describe Badline::Storage, ".reopen" do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:disk) do
    File.join(dir, "disk.d64").tap { |file| blank_d64(file) }
  end

  after { FileUtils.remove_entry(dir) }

  def reopened(storage, detached:)
    out = Badline::Snapshot::StateWriter.new
    storage.save_setup(out)
    described_class.reopen(Badline::Snapshot::StateReader.new(out.state, detached:))
  end

  it "opens a disk image as it was" do
    expect(reopened(Badline::Storage::D64Image.new(disk), detached: false)).to be_writable
  end

  it "opens a disk image write-protected for a detached reader" do
    expect(reopened(Badline::Storage::D64Image.new(disk), detached: true)).not_to be_writable
  end

  it "leaves a directory's files alone for a detached reader" do
    storage = reopened(Badline::Storage::HostDirectory.new(dir), detached: true)
    expect { storage.write_file("NEW", [1, 2], type: :prg) }.to raise_error(Badline::Storage::WriteError)
  end

  it "finds no files in a directory for a detached reader" do
    File.binwrite(File.join(dir, "prog.prg"), "\x01\x08".b)
    expect(reopened(Badline::Storage::HostDirectory.new(dir), detached: true).read_file("PROG")).to be_nil
  end
end
