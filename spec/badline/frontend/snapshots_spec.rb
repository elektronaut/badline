# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Snapshots do
  subject(:snapshots) { described_class.new(computer, options) }

  let(:computer) { Badline::Computer.new }
  let(:options) { Badline::Options.parse([]) }
  let(:quicksaves) { File.join(Badline.data_path, "quicksaves") }
  let(:saves) { File.join(Badline.data_path, "saves") }

  around do |example|
    Dir.mktmpdir do |dir|
      Badline.data_path = dir
      quietly { example.run }
    end
  ensure
    Badline.data_path = nil
  end

  def quietly
    stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = stdout
  end

  def quicksave(times = 1) = times.times { snapshots.quicksave }

  def slot(number) = File.join(quicksaves, "quicksave-#{number}.vsf")

  # Writes a snapshot of the machine at path, modified the given seconds ago.
  def snapshot_at(path, age)
    FileUtils.mkdir_p(File.dirname(path))
    computer.save_snapshot(path)
    time = Time.now - age
    File.utime(time, time, path)
  end

  describe "#quicksave" do
    it "saves to the first slot in the data folder's quicksaves" do
      quicksave
      expect(Dir.children(quicksaves)).to eq(["quicksave-1.vsf"])
    end

    it "says which slot it saved" do
      expect { quicksave(2) }.to output(/Saved quicksave 2 to .*quicksave-2\.vsf/).to_stdout
    end

    it "keeps five slots" do
      quicksave(7)
      expect(Dir.children(quicksaves).sort).to eq((1..5).map { |n| "quicksave-#{n}.vsf" })
    end

    it "replaces the oldest once every slot is used" do
      [3, 1, 5, 2, 4].each_with_index { |number, age| snapshot_at(slot(number), 10 - age) }
      expect { quicksave }.to output(/Saved quicksave 3 /).to_stdout
    end

    it "warns when the quicksaves folder can't be made" do
      File.write(quicksaves, "")
      expect { quicksave }.to output(/badline: quicksave: /).to_stderr
    end
  end

  describe "#restore" do
    it "says there's nothing to restore in an empty folder" do
      expect { snapshots.restore }.to output(/No quicksave to restore. F11: Quicksave/).to_stdout
    end

    it "leaves the machine in place when there's nothing to restore" do
      snapshots.restore
      expect(snapshots.computer).to be(computer)
    end

    it "restores the newest quicksave" do
      snapshot_at(slot(1), 5)
      snapshot_at(slot(2), 10)
      expect { snapshots.restore }.to output(/Restored quicksave 1 from /).to_stdout
    end

    it "restores the newest quicksave saved before a restart" do
      quicksave(3)
      expect { described_class.new(computer, options).restore }.to output(/Restored quicksave 3 /).to_stdout
    end

    it "runs the restored machine in place of the one before" do
      quicksave
      snapshots.restore
      expect(snapshots.computer).not_to be(computer)
    end

    it "picks a named save that's newer than every quicksave" do
      snapshot_at(slot(1), 10)
      snapshot_at(File.join(saves, "level 2.vsf"), 5)
      expect { snapshots.restore }.to output(/Restored level 2 from /).to_stdout
    end

    it "never picks an autosave" do
      snapshot_at(slot(1), 10)
      snapshot_at(File.join(Badline.data_path, "autosaves", "exit.vsf"), 5)
      expect { snapshots.restore }.to output(/Restored quicksave 1 /).to_stdout
    end

    it "warns when the quicksaves folder can't be made" do
      File.write(quicksaves, "")
      expect { snapshots.restore }.to output(/badline: quicksave: /).to_stderr
    end

    it "warns when the newest won't open" do
      FileUtils.mkdir_p(quicksaves)
      File.write(slot(1), "not a snapshot")
      expect { snapshots.restore }.to output(/quicksave-1\.vsf: /).to_stderr
    end
  end
end
