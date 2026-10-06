# frozen_string_literal: true

# Which rows bin/testbench --vic20 runs, from vic20-testlist.in, and the
# machine each asks for. The machine-driving half is in
# test/testbench_vic20_machine.rb, which the Spinel build shares.
module Testbench
  VIC20_TESTLIST = File.expand_path("../vendor/VICE-testprogs/testbench/vic20-testlist.in", __dir__)

  # The RAM configuration each memory option asks for, as xvic's -memory
  # fits it: BLK1 for vic20-8k, and every block for vic20-32k, which xvic
  # starts with -memory all. A row with neither, or vic20-unexp, runs
  # unexpanded.
  VIC20_RAM = { "vic20-8k" => :"8k", "vic20-32k" => :all }.freeze

  # A GEO-RAM, which badline doesn't fit to the VIC-20.
  VIC20_SKIP_OPTIONS = /\Ageo512k\z/

  # A TestCase's machine, when the row is the VIC-20's, and its run.
  module Vic20Row
    def vic20? = family == :vic20

    def ram_configuration
      options.filter_map { |option| VIC20_RAM[option] }.first || :unexpanded
    end

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def vic20_machine = Testbench.vic20_machine(ram_configuration, cartridge.nil?)

    # Runs the row on +machine+, returning the exit code and the text
    # screen.
    def run_vic20(machine)
      exit_code = Vic20Execution.new(machine).run((cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, Testbench.vic20_screen_text(machine)]
    end
  end

  # The VIC-20 testlist's exitcode rows. Screenshot rows wait for the
  # VIC-I's video, and interactive rows are left out as on the C64. A
  # mountcrt row starts from power-on with its cartridge in, as a C64
  # cartridge row does.
  module Vic20Testlist
    module_function

    def tests(filters, scope: nil, exclude: nil)
      Testlist.numbered(File.readlines(VIC20_TESTLIST).filter_map { |line| parse(line) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless type == "exitcode"
      return if options.any?(VIC20_SKIP_OPTIONS)

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, Testlist.cartridge(options))
      test.family = :vic20
      test if runnable?(test)
    end

    def runnable?(test)
      return File.exist?(File.join(test.dir_abs, test.prg)) unless test.cartridge

      test.prg.empty? && File.exist?(test.cartridge_path)
    end
  end
end
