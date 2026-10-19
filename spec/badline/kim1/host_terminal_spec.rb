# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

  describe ".start" do
    def start(text)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "game.ptp")
        File.write(path, text)
        console = console_class.new("", 0)
        [described_class.start(Badline::Options.parse(["kim1", "--headless", path]), console), console.printed]
      end
    end

    it "loads the program the command line names" do
      status, printed = start(";010200EA00ED\n;0000010001\n")
      expect([status, printed.lines.first]).to start_with(0).and(end_with(/at \$0200\r\n/))
    end

    # What the block returns, and what it warned.
    def warned
      original = $stderr
      $stderr = StringIO.new
      [yield, $stderr.string]
    ensure
      $stderr = original
    end

    it "fails on a program that won't load, and says why" do
      expect(warned { start(";010200EA00EE\n").first }).to match([1, /bad checksum/])
    end
  end
end
