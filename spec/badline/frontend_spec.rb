# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../support/sdl_dummy_drivers"

describe Badline::Frontend do
  include_context "with SDL's dummy drivers"

  def run(*argv) = described_class.run(Badline::Options.parse(argv))

  it "plays the machine and returns 0" do
    expect(run("--frames", "1", "--unpaced")).to eq(0)
  end

  it "warns about media that won't attach and returns 1" do
    File.write("bad.crt", "junk")
    expect { run("bad.crt") }.to output(/badline-ruby: bad.crt: Missing CRT signature/).to_stderr
  end

  describe "an --at insert that fails" do
    def insert_bad = run("--unpaced", "--frames", "5", "--at", "1:insert=bad.crt")

    before { File.write("bad.crt", "junk") }

    it "warns" do
      expect { insert_bad }.to output(/badline-ruby: bad\.crt: Missing CRT signature/).to_stderr
    end

    it "returns 1" do
      allow($stderr).to receive(:write)
      expect(insert_bad).to eq(1)
    end
  end

  it "restores a .vsf" do
    Badline::Computer.new.save_snapshot("saved.vsf")
    expect { run("saved.vsf", "--frames", "1", "--unpaced") }.to output(/Restored saved.vsf/).to_stdout
  end

  it "builds an NTSC machine with --ntsc" do
    allow(Badline::Frontend::App).to receive(:new).and_return(instance_double(Badline::Frontend::App, run: nil))
    run("--ntsc")
    expect(Badline::Frontend::App).to have_received(:new).with(having_attributes(region: Badline::Region::NTSC),
                                                               anything, anything)
  end
end
