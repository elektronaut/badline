# frozen_string_literal: true

# Which rows bin/testbench --c128c64 runs, from the x128c64 testlist, and
# the C128 each asks for. The machine-driving half is in
# test/support/testbench_c128_machine.rb, which the Spinel build shares.
module Testbench
  # VICE-testprogs generates x128c64-testlist.txt from c64-testlist.in: its
  # Makefile drops the rows with these options, which x128 has no machine
  # for, and renames cpuport.prg to the C128's build of it.
  C128C64_DROPPED = %w[,vicii-ntscold ,vicii-drean ,plus60k ,plus256k].freeze

  # The curated suite: the x128c64 rows where a C128 in C64 mode can differ
  # from a C64C. Those are the subtrees that reach the VIC-IIe, the 8502
  # and its port, the interrupt lines, the C128's bus and I/O map, its
  # power-on state and the cartridge port: VICII, CPU, interrupts, C64,
  # general and the testbench's own selftest. The rows of the other
  # subtrees exercise the same CIA, SID, drive and REU classes on either
  # machine, so the C64's suites keep them.
  #
  # Within those subtrees a row drops out when it asks for:
  # - the 6569 (vicii-old): a C128 has only the 8566 or the 8564
  # - a memory expansion: the REU stays off the C128 in this phase
  # - a disk image or a true drive, which testbench-drive covers
  # - a cartridge type badline has no mapper for
  # CPU/decimalmode and the Lorenz suite drop out as in the C64's suites,
  # bar the Lorenz cpuport128 row, the one row the x128c64 list changes.
  # interrupts/irqdma drops out for CI time: 19 rows of about 450M cycles
  # on the same CPU and VIC sequencer that testbench-irqdma runs.
  C128C64_DIRS = %r{\A\.?\./(VICII|CPU|interrupts|C64|general|selftest)/}
  C128C64_EXCLUDED_DIRS = %r{\A\.\./(CPU/decimalmode|interrupts/irqdma|general/Lorenz-2\.15)/}
  C128C64_LORENZ_ROW = "general/Lorenz-2.15/src/cpuport128.prg"
  VICII_OLD_OPTION = "vicii-old"

  # The rows of the x128 testlist that need C128 mode, the MMU, the VDC or
  # the VIC-IIe's 2 MHz mode alone. The rest need the Z80 (c128/z80, and
  # the c64modez80 and c128modez80 programs beside c64modemmu, which
  # --c128-z80 runs), a memory expansion or a C128 cartridge, or are
  # interactive. VDC/vdcdump runs for 1.75G cycles, which is left out for
  # CI time.
  C128_DIRS = %r{\A\.?\./(selftest|c128/(mmu|c64modemmu|ram0001|ram0001mmu|vic-mmu|vdccrash|2mhzVIC|d030tester))/?\z}

  # The rows that need a true drive, which run with the disk image they
  # mount in it: a 1571 for a .d71 or .g71 and a 1541 for a .d64 or .g64,
  # as x128's hooks pick the drive.
  C128_DRIVE_DIRS = %r{\A\.\./(c128/burstmode|drive/scanner)/?\z}
  Z80_PROGRAM = /z80/

  # A TestCase's C128: a row of the x128c64 list, in C64 mode, or of the
  # x128 list, in C128 mode.
  module C128Row
    def c128? = %i[c128 c128_mode].include?(family)

    # The mode the row's C128 powers on in.
    def c128_mode = family == :c128_mode ? :c128 : :c64

    # The board the row's CIAs and video standard ask for: the C128DCR
    # for cia-new's 6526As, and the NTSC board for vicii-ntsc. The SID is
    # the board's, since no row of the suite asks for one.
    def c128_model
      board = cia_model == :mos6526a ? "c128dcr" : "c128"
      ntsc? ? "#{board}ntsc" : board
    end

    # The true drive a row of the x128 testlist runs with: "1571" for a
    # .d71 or .g71, "1541" for a .d64 or .g64, and nil for none.
    def c128_drive
      return unless disk && family == :c128_mode

      disk.end_with?("71") ? "1571" : "1541"
    end

    # The machine the row's tests fork from: booted, with its true drive
    # when it has one, or at power-on for a cartridge.
    def c128_machine
      drive = c128_drive
      return Testbench.c128_drive_machine(c128_model, c128_mode, drive) if drive

      Testbench.c128_machine(c128_model, cartridge.nil?, c128_mode)
    end
  end

  # The rows of the x128 testlist for C128 mode (C128_DIRS), or those that
  # need the Z80, each on a C128 that powers on in C128 mode, its Z80
  # booting it.
  module C128ModeTestlist
    module_function

    # The rows that need C128 mode alone, or with +z80+ the rows that need
    # the Z80.
    def tests(filters, scope: nil, exclude: nil, z80: false)
      testlist = File.join(TESTBENCH_DIR, "c128-testlist.in")
      C128Testlist.numbered(File.readlines(testlist).filter_map { |line| parse(line, z80:) })
                  .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, z80: false)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless RUNNABLE_TYPES.include?(type) && z80_row?(dir, prg) == z80
      return unless Testlist.cartridge(options).nil?

      disk = Testlist.disk(options)
      return unless z80 || runnable_dir?(dir, disk)

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, nil)
      test.disk = disk
      test.family = :c128_mode
      test
    end

    # A row of C128_DIRS, or of C128_DRIVE_DIRS with a disk to mount.
    def runnable_dir?(dir, disk)
      dir.match?(C128_DIRS) || (!disk.nil? && dir.match?(C128_DRIVE_DIRS))
    end

    # A row that needs the Z80: the c128/z80 programs, and the c64modez80
    # and c128modez80 programs beside c64modemmu.
    def z80_row?(dir, prg) = dir.include?("/z80/") || prg.match?(Z80_PROGRAM)
  end

  # The curated rows of the x128c64 testlist (C128C64_DIRS).
  module C128Testlist
    module_function

    def tests(filters, scope: nil, exclude: nil)
      numbered(File.readlines(TESTLIST).filter_map { |line| parse(line) })
        .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    # Counted by id alone, since one suite holds both video standards and
    # both CIAs: a program listed for PAL and NTSC keys its second row #2.
    def numbered(tests)
      seen = Hash.new(0)
      tests.each { |test| test.occurrence = seen[test.id] += 1 }
    end

    def parse(line)
      line = line.strip
      return if dropped?(line)

      dir, prg, type, timeout, *options = line.sub("cpuport.prg", "cpuport128.prg").split(",")
      return unless RUNNABLE_TYPES.include?(type)
      return if options.any?(SKIP_OPTIONS) || options.include?(VICII_OLD_OPTION)

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, Testlist.cartridge(options))
      test.disk = Testlist.disk(options)
      test.family = :c128
      test if runnable?(test, dir)
    end

    # A blank line, a comment, or a row the Makefile drops for x128.
    def dropped?(line)
      line.empty? || line.start_with?("#") || C128C64_DROPPED.any? { |option| line.include?(option) }
    end

    def runnable?(test, dir)
      return false unless included?(test, dir)
      return false if test.expansion || test.drive? || Testbench::NOT_APPLICABLE.include?(test.id)

      test.cartridge.nil? || Testlist.runnable_cartridge?(test)
    end

    def included?(test, dir)
      return true if test.id == C128C64_LORENZ_ROW

      dir.match?(C128C64_DIRS) && !dir.match?(C128C64_EXCLUDED_DIRS)
    end
  end
end
