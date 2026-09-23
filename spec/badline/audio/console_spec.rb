# frozen_string_literal: true

require "spec_helper"
require "stringio"

describe Badline::Audio::Console do
  subject(:console) { described_class.new(input: reader, output:) }

  let(:pipe) { IO.pipe }
  let(:reader) { pipe.first }
  let(:output) { StringIO.new }

  after { pipe.each(&:close) }

  def press(keys) = pipe.last.write(keys)

  describe "#wait" do
    {
      "n" => :next, "\e[C" => :next,
      "p" => :previous, "\e[D" => :previous,
      " " => :pause, "q" => :quit
    }.each do |key, action|
      it "reads #{key.inspect} as #{action}" do
        press(key)
        expect(console.wait(0)).to eq([action])
      end
    end

    it "reads every key waiting, in order" do
      press("n p\e[Cq")
      expect(console.wait(0)).to eq(%i[next pause previous next quit])
    end

    it "ignores keys it has no use for" do
      press("x\e[A")
      expect(console.wait(0)).to eq([])
    end

    it "returns nothing once the time is up" do
      expect(console.wait(0.01)).to eq([])
    end

    context "when the input has closed" do
      before { pipe.last.close }

      it "still waits out the time" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        2.times { console.wait(0.02) }
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.04
      end
    end
  end

  describe "#status" do
    it "redraws the line in place" do
      console.status(song: 3, songs: 12, elapsed: 75.4, length: 185.0)
      expect(output.string).to eq("\r\e[Ksong 3/12  1:15 / 3:05")
    end

    it "appends its notes" do
      console.status(song: 1, songs: 1, elapsed: 0, length: 60, notes: ["paused"])
      expect(output.string).to end_with("0:00 / 1:00  paused")
    end
  end

  describe "#header" do
    it "prints each line, then the keys" do
      console.header(%w[Tune Author])
      expect(output.string).to eq("Tune\r\nAuthor\r\nn/→ next  p/← previous  space pause  q quit\r\n")
    end
  end

  describe "#session" do
    it "hides the cursor for the block and shows it again after" do
      console.session { output.print "x" }
      expect(output.string).to eq("\e[?25lx\e[?25h\r\n")
    end

    context "when the block raises" do
      before do
        console.session { raise Interrupt }
      rescue Interrupt
        nil
      end

      it "shows the cursor again" do
        expect(output.string).to end_with("\e[?25h\r\n")
      end
    end
  end
end
