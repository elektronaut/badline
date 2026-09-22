# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/lorenz_cia_timer"
require_relative "../../support/cia_timer_replay"

# Mirrors Wolfgang Lorenz's cia1ta and cia1tb, old-CIA build: the cells of
# each 20832-cell sweep, replayed against a bare CIA and checked against the
# results transcribed from cia1ta.s. The real tests take about 25 minutes on
# the chain when they fail. Pinned by cia1ta and cia1tb (the CIA 6526 timer
# pipeline in doc/pinned-behaviour.md).
describe Badline::CIA::Timer do
  describe "Lorenz timer grid" do
    def mismatches(timer, cells)
      cells.filter_map do |cell|
        got = CiaTimerReplay.run(timer, *cell)
        want = LorenzCiaTimer.expected(timer, *cell)
        next if got == want

        "cell #{cell.map { format('%02x', it) }.join(' ')}: got #{got}, want #{want}"
      end.first(20)
    end

    # Every 7th cell: 7 shares no factor with the 32 control combinations or
    # the 21 latch values, so the sample still covers every combination.
    let(:sample) { LorenzCiaTimer.cells.each_slice(7).map(&:first) }

    it "matches a sample of cia1ta cells" do
      expect(mismatches(:a, sample)).to be_empty
    end

    it "matches a sample of cia1tb cells" do
      expect(mismatches(:b, sample)).to be_empty
    end

    it "matches every cia1ta cell", :slow do
      expect(mismatches(:a, LorenzCiaTimer.cells)).to be_empty
    end

    it "matches every cia1tb cell", :slow do
      expect(mismatches(:b, LorenzCiaTimer.cells)).to be_empty
    end
  end
end
