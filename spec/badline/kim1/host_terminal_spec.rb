# frozen_string_literal: true

require "spec_helper"

describe Badline::KIM1::HostTerminal do
  # A terminal that types `typed` once, prints into `printed`, and ends
  # the session with Ctrl-C after `steps` reads.
  let(:console_class) do
    Class.new do
      attr_reader :printed

      def initialize(typed, steps)
        @typed = typed
        @steps = steps
        @printed = +""
      end

      def typing = yield

      def read_text(_seconds)
        @steps -= 1
        raise Interrupt if @steps.negative?

        text = @typed
        @typed = ""
        text
      end

      def print_text(text)
        @printed << text
      end
    end
  end

  let(:kim) { Badline::KIM1.new(tty: true) }

  it "types what the terminal types, and prints what the teletype prints" do
    console = console_class.new("x", 1)
    kim.teletype.output << "\x00KIM\x7f\r\n"
    described_class.run(kim, console)
    expect([console.printed.lines.last, kim.teletype.busy?]).to eq(["KIM\r\n", true])
  end

  it "ends with Ctrl-C, as a success" do
    expect(described_class.run(kim, console_class.new("", 0))).to eq(0)
  end
end
