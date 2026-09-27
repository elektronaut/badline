# frozen_string_literal: true

require "spec_helper"
require_relative "../native/pack"

describe NativePack do
  let(:info) { { version: "0.4.0", revision: "v0.4.0", spinel: "spinel 2026.09.12+1184 (15f037af)" } }

  describe ".spin_toml" do
    it "lists the load path as path dependencies, in order" do
      expect(described_class.spin_toml(["/a/lib", "/b/lib"]))
        .to eq("[package]\nname = \"badline\"\n\n[dependencies]\n" \
               "load_path_0 = { path = \"/a/lib\" }\nload_path_1 = { path = \"/b/lib\" }\n")
    end
  end

  describe ".spinel_release" do
    it "leaves out the C compiler Spinel was built with" do
      expect(described_class.spinel_release("spinel 2026.09.12+1184 (15f037af) [apple clang 21.0.0 (cc)]"))
        .to eq("spinel 2026.09.12+1184 (15f037af)")
    end
  end

  describe ".spinel_commit" do
    it "is the revision in the version's parentheses" do
      expect(described_class.spinel_commit("spinel 2026.09.12+1184 (15f037af)")).to eq("15f037af")
    end

    it "is unknown when the version names none" do
      expect(described_class.spinel_commit("spinel")).to eq("unknown")
    end
  end

  describe ".tarball" do
    it "names the badline version and the Spinel commit" do
      expect(described_class.tarball(info)).to eq("tmp/native/badline-0.4.0-spinel-15f037af.tar.gz")
    end
  end

  describe ".manifest" do
    it "records the version, the revision and the compiler" do
      expect(described_class.manifest(info))
        .to eq("badline 0.4.0\nrevision v0.4.0\nspinel 2026.09.12+1184 (15f037af)\n")
    end
  end
end
