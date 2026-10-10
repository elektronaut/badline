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

      # A new machine, built as the snapshot's was and restored from it. A
      # badline snapshot restores from its BADLINE module alone, which
      # carries everything its VICE modules do, and a VICE one through the
      # modules badline reads. xvic's and x128's own modules aren't read.
      # Yields a line for each thing left out, or warns it without a block.
      def load(&)
        raise FormatError, "badline reads only its own VIC-20 snapshots, not xvic's" if vic20? && !badline?
        raise FormatError, "badline reads only its own C128 snapshots, not x128's" if c128? && !badline?

        computer = badline? ? opening { Setup.restored(state) } : Vice.setup(@container).build
        tell(badline? ? state_report(computer) : Vice::Restore.apply(@container, computer), &)
        computer
      end

      # Whether the machine is a VIC-20, as the container names it.
      def vic20? = @container.machine == Container::VIC20

      # Whether the machine is a C128, as the container names it.
      def c128? = @container.machine == Container::C128

      # Restores `computer` from the snapshot, and returns the Report. A
      # snapshot that fails leaves the machine as it was.
      def restore(computer, &)
        report = badline? ? restore_state(computer) : Vice::Restore.import(@container, computer)
        tell(report, &)
        report
      end

      private

      def section = @container[MachineState::NAME]

      def tell(report)
        report.ignored.each { |line| block_given? ? yield(line) : warn("badline: #{line}") }
      end

      def restore_state(computer)
        opening { computer.restore(state) }
        state_report(computer)
      end

      def opening
        yield
      rescue SystemCallError => e
        raise FormatError, "a file the snapshot names won't open: #{e.message}"
      end

      def state_report(computer)
        lost = computer.init_handlers_lost
        ignored = lost.positive? ? ["#{lost} on_init handler(s) the saved machine had yet to run, left out"] : []
        Report.new(applied: [MachineState::NAME], ignored:)
      end
    end
  end
end
