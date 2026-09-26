# frozen_string_literal: true

require "spec_helper"
require_relative "../../native/lib/badline/native/build_info"
require_relative "../../native/lib/badline/native/version"

describe Badline::Native do
  describe ".version" do
    it "names the badline version, the revision and the Spinel build" do
      expect(described_class.version(revision: "v0.3.0-4-g1234abcd", spinel: "spinel 2026.09.12+1155 (9346225f)"))
        .to eq("badline #{Badline::VERSION} (v0.3.0-4-g1234abcd) built with spinel 2026.09.12+1155 (9346225f)")
    end

    it "leaves out a revision it doesn't know" do
      expect(described_class.version(revision: "", spinel: "spinel 2026.09.12"))
        .to eq("badline #{Badline::VERSION} built with spinel 2026.09.12")
    end

    it "says when it doesn't know the compiler, as in a build by hand" do
      expect(described_class.version(revision: "", spinel: ""))
        .to eq("badline #{Badline::VERSION} built with an unknown Spinel")
    end
  end
end
