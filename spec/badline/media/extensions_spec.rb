# frozen_string_literal: true

require "spec_helper"

describe Badline::Media::Extensions do
  describe ".kind" do
    {
      "game.d64" => :disk, "GAME.D81" => :disk, "game.g71" => :gcr, "game.t64" => :archive, "game.tap" => :tape,
      "game.crt" => :cartridge, "tune.sid" => :tune, "set.vfl" => :disk_list, "game.p00" => :program, "game" => :program
    }.each do |name, kind|
      it "takes #{name} for #{kind}" do
        expect(described_class.kind("/media/#{name}")).to eq(kind)
      end
    end
  end

  describe ".of" do
    it "lists the extensions of the kinds given" do
      expect(described_class.of(%i[tape disk_list])).to eq(%w[.tap .m3u .vfl])
    end
  end

  it "has the disk images a drive reads" do
    expect(described_class::DISKS).to eq(%w[.d64 .d71 .d81 .g64 .g71])
  end

  it "has what the traps mount, which Media opens" do
    expect(described_class::MOUNTABLE).to eq(Badline::Media::MOUNT_TYPES.keys)
  end
end
