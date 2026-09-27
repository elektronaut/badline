# frozen_string_literal: true

module Badline
  module Snapshot
    # What a restore applied and what it left out: module names, and a line
    # for each module left out, saying why.
    Report = Data.define(:applied, :ignored)

    # A snapshot read from a file.
    class Image
      attr_reader :container

      def initialize(container)
        @container = container
      end

      def sections = @container.sections

      # Whether badline wrote it, with the whole machine in a BADLINE module.
      def badline? = !state.nil?

      # A machine at power-on with the snapshot's chip models.
      def to_computer
        Computer.new(**(state ? MachineState.models(state) : Vice.models(@container)))
      end

      # Restores `computer` from the snapshot. A badline snapshot restores
      # from its BADLINE module alone, which carries everything its VICE
      # modules do, and a VICE one through the modules badline reads.
      # Yields a line for each module left out, or warns it without a
      # block.
      def restore(computer)
        report = state ? restore_state(computer) : Vice.import(@container, computer)
        report.ignored.each { |line| block_given? ? yield(line) : warn("badline: #{line}") }
        report
      end

      private

      def state = @container[MachineState::NAME]

      def restore_state(computer)
        MachineState.restore(state, computer)
        Report.new(applied: [MachineState::NAME], ignored: [])
      end
    end
  end
end
