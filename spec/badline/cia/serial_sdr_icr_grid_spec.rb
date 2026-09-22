# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cia_sdr_icr"

# Mirrors CIA/shiftregister/cia-sdr-icr: the test loop replayed against a
# bare CIA for every timer A latch the _7f sweeps walk (0 to 127), checked
# against the program's own references. Pinned by the cia-sdr-icr rows (the
# CIA serial shift register in doc/pinned-behaviour.md): empty at the 15th
# underflow, the in-flight delay line, the latched level and the zero-latch
# stall.
describe Badline::CIA::Serial do
  describe "cia-sdr-icr grid", :slow do
    def self.results = @results ||= (0..127).to_h { |baud| [baud, CiaSdrIcr::Replay.run(baud)] }

    # The bauds whose results differ from the reference, with the first
    # differing sample.
    def mismatches(type)
      self.class.results.filter_map do |baud, (results1, results2)|
        first1 = results1.zip(CiaSdrIcr::Reference.results1(baud)).index { |got, want| got != want }
        first2 = results2.zip(CiaSdrIcr::Reference.results2(baud, type)).index { |got, want| want && got != want }
        next unless first1 || first2

        "baud #{baud}: results1[#{first1.inspect}] results2[#{first2.inspect}]"
      end
    end

    it "passes every baud against the normal reference" do
      expect(mismatches(:normal)).to be_empty
    end

    it "passes every baud against the generic reference" do
      expect(mismatches(:generic)).to be_empty
    end

    # The 4485 rows are expect:error, except at baud 0, which that batch
    # shares; baud 1 agrees too.
    it "fails the 4485 reference from baud 2 up" do
      expect(mismatches(:c4485).map { it[/\d+/].to_i }).to eq((2..127).to_a)
    end
  end
end
