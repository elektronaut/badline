# frozen_string_literal: true

module Badline
  module Snapshot
    # What a restore applied and what it left out: module names, and a line
    # for each thing left out, saying why.
    Report = Data.define(:applied, :ignored)

    # A snapshot read from a file.
    class Image
      attr_reader :container

      def initialize(container)
        @container = container
      end

      def sections = @container.sections

      # Whether badline wrote it, with the whole machine in a BADLINE module.
      def badline? = !section.nil?

      # The State the BADLINE module holds.
      def state = MachineState.state(section)

      # A machine at power-on, built as the snapshot's was.
      def to_computer
        (badline? ? Computer.setup(state) : Vice.setup(@container)).build
      end

      # Restores `computer` from the snapshot. A badline snapshot restores
      # from its BADLINE module alone, which carries everything its VICE
      # modules do, and a VICE one through the modules badline reads.
      # Yields a line for each thing left out, or warns it without a block.
      def restore(computer)
        report = badline? ? restore_state(computer) : Vice.import(@container, computer)
        report.ignored.each { |line| block_given? ? yield(line) : warn("badline: #{line}") }
        report
      end

      private

      def section = @container[MachineState::NAME]

      def restore_state(computer)
        begin
          computer.restore(state)
        rescue SystemCallError => e
          raise FormatError, "a file the snapshot names won't open: #{e.message}"
        end
        lost = computer.init_handlers_lost
        ignored = lost.positive? ? ["#{lost} on_init handler(s) the saved machine had yet to run, left out"] : []
        Report.new(applied: [MachineState::NAME], ignored:)
      end
    end
  end
end
