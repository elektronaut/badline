# frozen_string_literal: true

module Badline
  module Snapshot
    # What a restore applied and what it left out: module names and a line
    # for each thing left out or changed, saying why. For a badline
    # snapshot, `modules` holds each BL-* module's Keyed::Report, which
    # give the fields per module this badline doesn't know, the modules it
    # expected and didn't find, and the values it read other than as
    # written, and `written_by` the badline version that saved it.
    class Report
      attr_reader :applied, :ignored, :written_by

      def initialize(applied:, ignored:, modules: [], written_by: "")
        @applied = applied
        @ignored = ignored
        @modules = modules
        @written_by = written_by
      end

      # The keys nothing read, by module, for the modules that had any.
      def unknown
        @modules.reject { |report| report.unknown.empty? }.to_h { |report| [report.name, report.unknown] }
      end

      # The modules the snapshot didn't have.
      def missing = @modules.select(&:missing).map(&:name)

      # A line for each value read other than as written.
      def adjusted = @modules.flat_map { |report| report.adjusted.map { |line| "#{report.name}: #{line}" } }
    end

    # A snapshot: the container and its modules, read from a file or taken
    # of a machine in memory (.of).
    class Image
      MACHINE = "BL-MACHINE"
      FAMILIES = { "c64" => "C64", "vic20" => "VIC-20", "c128" => "C128", "plus4" => "Plus/4", "pet" => "PET",
                   "cbm2" => "CBM-II", "kim1" => "KIM-1" }.freeze

      # The snapshots VICE's emulators write that badline doesn't read, by
      # the machine their container names.
      UNREAD = {
        Container::VIC20 => "VIC-20 snapshots, not xvic's", Container::C128 => "C128 snapshots, not x128's",
        Container::PLUS4 => "Plus/4 snapshots, not xplus4's"
      }.freeze

      attr_reader :container

      # `name` is what a refusal calls the snapshot, such as its file's name.
      def initialize(container, name: "the snapshot")
        @container = container
        @name = name
      end

      # The machine's snapshot, saved as a file saves it: the machine runs
      # on to the end of the instruction its CPU is in, and of an REU
      # transfer under way (Machine::Settling), then writes its BL-*
      # modules.
      def self.of(computer)
        computer.settle_for_snapshot!
        new(Container.new(computer.save_modules, machine: machine_name(computer)))
      end

      # The snapshot with VICE's modules ahead of the BL-* ones for a C64,
      # a PET, a CBM-II's B series or a P500, so x64sc, xpet, xcbm2 or
      # xcbm5x0 opens it too. Raises FormatError for a Plus/4, whose
      # snapshots badline doesn't write for xplus4.
      def self.exported(computer)
        raise FormatError, "badline doesn't export a Plus/4's snapshot for VICE" if computer.family == :plus4
        raise FormatError, "VICE has no KIM-1 to open a snapshot of one" if computer.family == :kim1

        computer.settle_for_vice!
        sections = computer.save_modules
        case computer.family
        when :c64 then sections = Vice.export(computer) + sections
        when :pet then sections = Vice::PET.export(computer, sections) + sections
        when :cbm2 then sections = cbm2_export(computer, sections) + sections
        end
        new(Container.new(sections, machine: machine_name(computer)))
      end

      # xcbm2's or xcbm5x0's modules for a CBM-II.
      def self.cbm2_export(computer, sections)
        computer.is_a?(CBM2::P500) ? Vice::P500.export(computer, sections) : Vice::CBM2.export(computer, sections)
      end

      # The VICE emulator a machine's VICE modules are for.
      def self.vice_emulator(computer)
        case machine_name(computer)
        when Container::PET then "xpet"
        when Container::CBM2 then "xcbm2"
        when Container::CBM2_5X0 then "xcbm5x0"
        else "x64sc"
        end
      end

      # The machine as VICE's emulators name it.
      def self.machine_name(computer)
        case computer.family
        when :vic20 then Container::VIC20
        when :c128 then Container::C128
        when :plus4 then Container::PLUS4
        when :pet then Container::PET
        when :cbm2 then computer.is_a?(CBM2::P500) ? Container::CBM2_5X0 : Container::CBM2
        when :kim1 then Container::KIM1
        else Container::MACHINE
        end
      end

      # How the machine was built, from the family BL-MACHINE, read by
      # `machine`, names.
      def self.setup(machine)
        case machine.choice("family", FAMILIES.keys, "c64")
        when "vic20" then Vic20Setup.read_fields(machine)
        when "c128" then C128Setup.read_fields(machine)
        when "plus4" then Plus4Setup.read_fields(machine)
        when "pet" then PETSetup.read_fields(machine)
        when "cbm2" then CBM2Setup.read_fields(machine)
        when "kim1" then KIM1Setup.read_fields(machine)
        else C64Setup.read_fields(machine)
        end
      end

      def sections = @container.sections

      def to_s = @container.to_s

      def ==(other) = other.is_a?(Image) && to_s == other.to_s

      # Whether badline wrote it, with the whole machine in BL-* modules.
      def badline? = !@container[MACHINE].nil?

      # A new machine, built as the snapshot's was and restored from it. A
      # badline snapshot restores from its BL-* modules alone, and a VICE
      # one through the modules badline reads, x64sc's, xpet's, xcbm2's or xcbm5x0's. xvic's,
      # x128's and xplus4's own modules aren't read. Yields a line for
      # each thing left out, or warns it without a block. `detached`
      # restores it without the host's files (Keyed::Modules).
      def load(detached: false, &)
        refuse_old_layout
        refuse_unread
        return load_xpet(&) if pet? && !badline?
        return load_xcbm2(&) if cbm2? && !badline?
        return load_xcbm5x0(&) if p500? && !badline?
        return load_vice(&) unless badline?

        modules = Keyed::Modules.new(sections, detached:)
        computer = opening { Image.setup(modules.machine).build.load_modules(modules) }
        tell(report(modules, computer), &)
        computer
      end

      # Whether the machine is a VIC-20, as the container names it.
      def vic20? = @container.machine == Container::VIC20

      # Whether the machine is a C128, as the container names it.
      def c128? = @container.machine == Container::C128

      # Whether the machine is of the 264 series, as the container names it.
      def plus4? = @container.machine == Container::PLUS4

      # Whether the machine is a PET, as the container names it.
      def pet? = @container.machine == Container::PET

      # Whether the machine is a CBM-II's B series, as the container names
      # it.
      def cbm2? = @container.machine == Container::CBM2

      # Whether the machine is a P500, as the container names it.
      def p500? = @container.machine == Container::CBM2_5X0

      # Restores `computer` from the snapshot, and returns the Report. The
      # snapshot goes into a new machine first, so one that fails, or is of
      # a machine built another way, leaves `computer` as it was.
      def restore(computer, &)
        refuse_old_layout
        report = if badline? then restore_modules(computer)
                 elsif pet? then Vice::PET::Restore.import(@container, computer)
                 elsif cbm2? then Vice::CBM2::Restore.import(@container, computer)
                 elsif p500? then Vice::P500::Restore.import(@container, computer)
                 else Vice::Restore.import(@container, computer)
                 end
        tell(report, &)
        report
      end

      private

      def load_vice(&)
        computer = Vice.setup(@container).build
        tell(Vice::Restore.apply(@container, computer), &)
        computer
      end

      def load_xpet(&)
        computer = Vice::PET.setup(@container).build
        tell(Vice::PET::Restore.apply(@container, computer), &)
        computer
      end

      def load_xcbm2(&)
        computer = Vice::CBM2.setup(@container).build
        tell(Vice::CBM2::Restore.apply(@container, computer), &)
        computer
      end

      def load_xcbm5x0(&)
        computer = Vice::P500.setup(@container).build
        tell(Vice::P500::Restore.apply(@container, computer), &)
        computer
      end

      # The snapshot goes into a new machine first, so one that fails
      # leaves `computer` as it was.
      def restore_modules(computer)
        modules = Keyed::Modules.new(sections)
        family = modules.machine.choice("family", FAMILIES.keys, "c64")
        unless family == computer.family.to_s
          raise FormatError, "the snapshot is of a #{FAMILIES.fetch(family, family)}, " \
                             "not a #{FAMILIES.fetch(computer.family.to_s)}"
        end

        trial = Keyed::Modules.new(sections)
        opening { Image.setup(trial.machine).build.load_modules(trial) }
        opening { computer.load_modules(modules) }
        report(modules, computer)
      end

      def refuse_unread
        unread = UNREAD[@container.machine]
        raise FormatError, "badline reads only its own #{unread}" if unread && !badline?
      end

      # A snapshot from a badline before the keyed modules, which only the
      # version that saved it reads.
      def refuse_old_layout
        old = @container[MachineState::NAME]
        return if old.nil? || badline?

        version = MachineState.written_by(old)
        layout = "in the old snapshot layout, which this badline can't read."
        raise FormatError, "#{@name} was saved by an earlier badline #{layout}" if version.empty?

        raise FormatError, "#{@name} was saved by badline #{version} #{layout} It still opens in badline #{version}."
      end

      def tell(report)
        report.ignored.each { |line| block_given? ? yield(line) : warn("badline: #{line}") }
      end

      def opening
        yield
      rescue SystemCallError => e
        raise FormatError, "a file the snapshot names won't open: #{e.message}"
      end

      def report(modules, computer)
        written_by = modules.machine.text("written_by", "")
        reports = modules.readers.map(&:report)
        ignored = reports.flat_map(&:lines)
        ignored.concat(modules.unread.map { |name| "#{name}: badline doesn't read this module, left out" })
        lost = computer.init_handlers_lost
        ignored << "#{lost} on_init handler(s) the saved machine had yet to run, left out" if lost.positive?
        Report.new(applied: reports.reject(&:missing).map(&:name), ignored:, modules: reports, written_by:)
      end
    end
  end
end
