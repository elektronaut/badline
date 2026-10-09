# frozen_string_literal: true

# The VICE testbench runner. bin/testbench runs Testbench.main and
# documents its options.

lib = File.expand_path("../../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "badline"
require "badline/vic20"
require "badline/c128"
require "chunky_png"
require "etc"
require "tmpdir"
require_relative "forked_boot"
require_relative "regression"
require_relative "testbench_machine"
require_relative "testbench_drive"
require_relative "testbench_region"
require_relative "testbench_engine"
require_relative "testbench_vic20"
require_relative "testbench_vic20_machine"
require_relative "testbench_c128"
require_relative "testbench_c128_machine"
require_relative "cli"

module Testbench
  TESTBENCH_DIR = File.expand_path("../../vendor/VICE-testprogs/testbench", __dir__)
  TESTLIST = File.join(TESTBENCH_DIR, "c64-testlist.in")
  ARTIFACT_DIR = File.expand_path("../../tmp/testbench", __dir__)

  RUNNABLE_TYPES = %w[exitcode screenshot].freeze

  # The testlist subtrees for hardware badline models. CPU/decimalmode is
  # left out of CPU: 41 exhaustive ADC/SBC sweeps that SingleStepTests
  # already covers per-opcode against bus-level reference traces, for a
  # worst case near nine hours. The Lorenz suite in general/ runs as
  # bin/lorenz's chain instead.
  INCLUDED_DIRS = %r{\A\.\./(VICII|CIA|interrupts|CPU|C64|general)/}
  EXCLUDED_DIRS = %r{\A\.\./(CPU/decimalmode|general/Lorenz-2\.15)/}

  # The Lorenz suite's 6526 half runs as bin/lorenz's chain off
  # Lorenz.d81, but nothing chains the 6526A half, so its cia-new rows run
  # here.
  LORENZ_DIR = %r{\A\.\./general/Lorenz-2\.15/}

  # P64 images and memory expansions other than GEO-RAM, the +60K, the
  # +256K and the REU are not emulated. A mountcrt row runs only under --carts, a drive
  # row or one that mounts a .d64 or a .g64 only under --drive, a cia-new
  # row, which asks for the 6526A, only under --cia-new, a vicii-new row,
  # which asks for the 8565, only under --vicii-new, a vicii-drean row only
  # under --drean, and a row that asks for an expansion in EXPANSIONS only
  # under --expansions.
  SKIP_OPTIONS = /mountp64|isepic|dqbb|ramcart/

  # A row the testlist comments out but tags vicii-drean, which runs under
  # --drean.
  COMMENTED_DREAN_ROW = /\A#\s*(\S+,vicii-drean(?:,\S*)?)\z/
  CARTRIDGE_OPTION = "mountcrt:"
  DISK_OPTION = /\Amount[dg](64|71):/

  # Rows that can't apply to badline. Both need a true 1541: they upload
  # code to the drive with M-W, start it with M-E and handshake with it
  # over the IEC lines, and badline's KERNAL traps stand in for the drive.
  # test-fuxxored runs ef2-inst1's drive check before it decodes the
  # program.
  NOT_APPLICABLE = %w[
    general/fuxxortest/test-fuxxored.prg
    general/fuxxortest/ef2-inst1.prg
  ].freeze
  CIA_NEW_OPTION = "cia-new"
  VICII_NEW_OPTION = "vicii-new"
  DEFAULT_MODELS = %i[mos6526 mos6569].freeze

  # The memory expansions a row can ask for, by testlist option, and the
  # REU sizes, reu128k to reu16m.
  EXPANSIONS = %w[geo512k plus60k plus256k].freeze
  REU_OPTION = /\Areu\d+[km]\z/

  # Pepto PAL palette (pepto-pal.vpl), which the references are rendered in.
  PALETTE = [
    0x000000, 0xFFFFFF, 0x68372B, 0x70A4B2, 0x6F3D86, 0x588D43, 0x352879,
    0xB8C76F, 0x6F4F25, 0x433900, 0x9A6759, 0x444444, 0x6C6C6C, 0x9AD284,
    0x6C5EB5, 0x959595
  ].freeze

  # The verdict and detail columns of a results row.
  def self.verdict(result)
    result == "PASS" ? "PASS\n" : "FAIL\t#{result}\n"
  end

  # family is :vic20 for a row of the VIC-20's testlist, :c128 for one of
  # the x128c64 list, and nil for the C64's.
  TestCase = Struct.new(:dir, :prg, :type, :timeout, :options, :cartridge, :occurrence, :disk, :family) do
    def id
      "#{dir.delete_prefix('../').delete_prefix('./')}/#{name}"
    end

    # The CIA the row asks for: the 6526A for cia-new, else the 6526.
    def cia_model
      options.include?(CIA_NEW_OPTION) ? :mos6526a : :mos6526
    end

    # The VIC-II the row asks for: the 8565 for vicii-new, else the 6569.
    # A C128 row gets the 8565, which the VIC-IIe is apart from its
    # registers.
    def vic_model
      options.include?(VICII_NEW_OPTION) || c128? ? :mos8565 : :mos6569
    end

    # The CIA and the VIC-II, the pair a suite's machine is built from.
    def models = [cia_model, vic_model]

    # The testlist option naming the memory expansion the row asks for, or
    # nil.
    def expansion
      options.find { |option| EXPANSIONS.include?(option) || option.match?(REU_OPTION) }
    end

    include DriveRow
    include RegionRow
    include Vic20Row
    include C128Row

    # The machine a VIC-20 or a C128 row forks from.
    def family_machine = vic20? ? vic20_machine : c128_machine

    # What tells a VIC-20 or C128 row's machine apart: the family, the
    # VIC-20's RAM and the C128's true drive.
    def family_key = [family, ram_configuration, c128_drive]

    def name
      return cartridge if prg.empty?

      cartridge ? "#{prg}+#{cartridge}" : prg
    end

    # Unique where the id is not: should the testlist run a program twice,
    # the baseline keys the second as id#2.
    def key
      occurrence.to_i > 1 ? "#{id}##{occurrence}" : id
    end

    # A test may declare that failing, or never reporting at all, is the
    # pass. Default is a $00 exit code.
    def expects
      return :error if options.include?("expect:error")
      return :timeout if options.include?("expect:timeout")

      :success
    end

    # exit_code is nil when the test never wrote $D7FF within its budget.
    def satisfied_by?(exit_code)
      case expects
      when :error then !exit_code.nil? && !exit_code.zero?
      when :timeout then exit_code.nil?
      else exit_code&.zero?
      end
    end

    def dir_abs
      File.expand_path(dir, Testbench::TESTBENCH_DIR)
    end

    def cartridge_path
      File.join(dir_abs, cartridge)
    end

    # The testlist budget, plus the boot for a test that loads a program.
    def budget
      prg.empty? ? timeout : timeout + BOOT_ALLOWANCE
    end

    # Seconds, which only catch a run stuck outside its emulated cycles: at
    # a hundred thousand cycles a second, far slower than any machine this
    # runs on, the budget alone would take that long. A true drive runs a
    # second CPU alongside, so its rows get twice that.
    def deadline
      60 + (budget / (drive? ? 50_000 : 100_000))
    end
  end

  # Which rows a run takes: the mountcrt rows or the others, the rows that
  # ask for the models, the CIA and the VIC-II, the rows that ask for a
  # memory expansion or the others, the rows that ask for the true drive
  # (see TestCase#drive_kind) or the others, and the rows of one video
  # standard (see TestCase#standard): :pal, :ntsc for either NTSC VIC-II,
  # or :drean for the 6572.
  Rows = Data.define(:carts, :models, :expansions, :drive, :standard) do
    def self.plain = new(carts: false, models: DEFAULT_MODELS, expansions: false, drive: nil)

    def initialize(carts:, models:, expansions:, drive:, standard: :pal) = super

    def include?(test)
      test.cartridge.nil? != carts && test.models == models && test.expansion.nil? != expansions &&
        test.drive_kind == drive && test.standard == standard
    end
  end

  module Testlist
    module_function

    # Filters are id substrings, matched as a union, and one led by "!"
    # leaves out the tests it matches (see Regression::Filters); no filter
    # runs everything inside the scope.
    def tests(filters, scope: nil, exclude: nil, rows: Rows.plain)
      numbered(File.readlines(TESTLIST).filter_map { |line| parse(line) })
        .select { |test| rows.include?(test) && selected?(test, filters, scope, exclude) }
    end

    # Counted over the whole testlist, so a key is the same whatever the
    # filters select, and separately for each CIA and VIC-II and for PAL,
    # NTSC and PAL-N: a program listed for both chips or several standards
    # keeps the key it has in each suite. A program listed for both NTSC
    # VIC-IIs takes #2 for the second.
    def numbered(tests)
      seen = Hash.new(0)
      tests.each { |test| test.occurrence = seen[[test.id, *test.models, test.standard]] += 1 }
    end

    def selected?(test, filters, scope, exclude)
      return false unless in_scope?(test, scope)
      return false if exclude && test.id.include?(exclude)

      Regression::Filters.parse(filters).selects?(test.id)
    end

    # A scope names one prefix, or several separated by commas.
    def in_scope?(test, scope)
      scope.nil? || scope.split(",").any? { |prefix| test.id.include?(prefix) }
    end

    # Filters that picked up no test at all, which a typo makes silent.
    def unmatched(filters, tests)
      Regression::Filters.parse(filters).picks.reject { |filter| tests.any? { |test| test.id.include?(filter) } }
    end

    def parse(line)
      line = line.strip
      line = line[COMMENTED_DREAN_ROW, 1] || line
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless RUNNABLE_TYPES.include?(type)
      return if options.any?(SKIP_OPTIONS)

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, cartridge(options))
      return if NOT_APPLICABLE.include?(test.id)

      test.disk = disk(options)
      test if runnable?(test, dir)
    end

    # A drive row runs from the drive/ subtree or one of the included
    # ones, while its disk image is there. A cartridge row that asks for a
    # memory expansion as well doesn't run.
    def runnable?(test, dir)
      return runnable_cartridge?(test) && test.disk.nil? && test.expansion.nil? if test.cartridge
      return File.exist?(File.join(test.dir_abs, test.prg)) if test.expansion
      return false unless dir.match?(DRIVE_DIR) || included?(dir, test.cia_model)

      test.disk.nil? || File.exist?(test.disk_path)
    end

    def included?(dir, cia_model)
      return dir.match?(LORENZ_DIR) if cia_model == :mos6526a && dir.start_with?("../general/")

      dir.match?(INCLUDED_DIRS) && !dir.match?(EXCLUDED_DIRS)
    end

    def disk(options)
      options.find { |option| option.match?(DISK_OPTION) }&.sub(DISK_OPTION, "")
    end

    def cartridge(options)
      options.find { |option| option.start_with?(CARTRIDGE_OPTION) }&.delete_prefix(CARTRIDGE_OPTION)
    end

    def runnable_cartridge?(test)
      return false unless File.exist?(test.cartridge_path)
      return false unless test.prg.empty? || File.exist?(File.join(test.dir_abs, test.prg))

      Badline::Cartridge::HARDWARE_TYPES.key?(Badline::Storage::CRTFile.new(test.cartridge_path).hardware_type)
    end
  end

  # Maps reference PNG pixels to C64 color indices by nearest palette entry.
  class ReferenceImage
    def initialize(path)
      @png = ChunkyPNG::Image.from_file(path)
      @indices = Hash.new { |cache, pixel| cache[pixel] = nearest(pixel) }
    end

    def size
      [@png.width, @png.height]
    end

    def row(line)
      Array.new(@png.width) { |x| @indices[@png[x, line]] }
    end

    private

    def nearest(pixel)
      rgb = [ChunkyPNG::Color.r(pixel), ChunkyPNG::Color.g(pixel),
             ChunkyPNG::Color.b(pixel)]
      (0..15).min_by { |i| distance(PALETTE[i], rgb) }
    end

    def distance(color, rgb)
      [(color >> 16) - rgb[0], ((color >> 8) & 0xff) - rgb[1],
       (color & 0xff) - rgb[2]].sum { |d| d * d }
    end
  end

  class Screenshot
    # A PAL screenshot, 384x272, has the display window's top left corner
    # at (32, 35), and an NTSC one, 384x247, at (32, 23). VICE compares two
    # screenshots on the rows they share with those corners lined up, so an
    # NTSC row that has only a PAL reference is compared on the rows both
    # views show.
    PAL_TOP = 35
    NTSC_TOP = 23

    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    # Returns the number of mismatched pixels and writes failure artifacts.
    def compare(test)
      reference = ReferenceImage.new(test.reference)
      width, height = reference.size
      return :ref_size unless width == WIDTH && [HEIGHT, NTSC_HEIGHT].include?(height)

      @skip = top(height) - top(rows.length)
      return :ref_size if @skip.negative?

      @shared = [rows.length, height - @skip].min
      diff = @shared.times.sum { |y| row_diff(reference.row(y + @skip), rows[y]) }
      write_artifacts(test, reference) if diff.positive?
      diff
    end

    private

    def top(height) = height == HEIGHT ? PAL_TOP : NTSC_TOP

    def row_diff(expected, actual)
      expected.each_index.count { |x| expected[x] != actual[x] }
    end

    def write_artifacts(test, reference)
      base = File.join(ARTIFACT_DIR, test.key.tr("/", "-"))
      to_png { |x, y| rows[y][x] }.save("#{base}.actual.png")
      to_png do |x, y|
        y >= @shared || reference.row(y + @skip)[x] == rows[y][x] ? rows[y][x] : nil
      end.save("#{base}.diff.png")
    end

    # Builds a PNG from palette indices; nil pixels are marked red.
    def to_png(&)
      png = ChunkyPNG::Image.new(WIDTH, rows.length)
      rows.length.times do |y|
        WIDTH.times do |x|
          index = yield(x, y)
          rgb = index ? PALETTE[index] : 0xFF0000
          png[x, y] = ChunkyPNG::Color.rgb(rgb >> 16, (rgb >> 8) & 0xff, rgb & 0xff)
        end
      end
      png
    end
  end

  # Tests are independent, so a run is split over forked shards.
  module Shards
    module_function

    # Longest budget first into the least loaded shard, each shard keeping
    # testlist order. An exitcode test ends when it reports, so the budget
    # is only an upper bound, but it is the one ordering available before
    # the run.
    def split(tests, count)
      groups = Array.new(count) { [] }
      loads = Array.new(count, 0)
      tests.each_with_index.sort_by { |test, _| -test.timeout }.each do |test, index|
        shard = loads.each_index.min_by { |n| loads[n] }
        groups[shard] << [index, test]
        loads[shard] += test.timeout
      end
      groups.map { |group| group.sort_by(&:first).map(&:last) }
    end
  end

  # Each row is appended the moment its test finishes, by whichever process
  # ran it, so a run that is killed keeps every row it finished and
  # --resume carries on from there. Rows are in the results format, keyed
  # the way the baseline reads them, so the file diffs against it too. One
  # small O_APPEND write per row keeps the shards' rows from interleaving.
  class Progress
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def append(test, result)
      File.write(@path, "#{test.key}\t#{Testbench.verdict(result)}", mode: "a")
    end

    # key => result. A row cut short by a kill has no newline and is left
    # to run again.
    def rows
      return {} unless File.exist?(@path)

      File.readlines(@path).select { |line| line.end_with?("\n") }.to_h do |line|
        key, verdict, detail = line.chomp.split("\t", 3)
        [key, verdict == "PASS" ? verdict : detail]
      end
    end

    def clear
      FileUtils.rm_f(@path)
    end
  end

  # A sharded run stopped by a signal, after its shards were stopped too.
  class Interrupted < StandardError
    attr_reader :signal

    def initialize(signal, progress)
      @signal = signal
      super("testbench interrupted by SIG#{signal}. No results written. " \
            "Finished rows are in #{progress}, and --resume carries on from them.")
    end
  end

  class Runner
    FORWARDED_SIGNALS = %w[TERM INT].freeze

    # CLI.shard_count, but one shard without fork.
    def self.shard_count(requested)
      return 1 unless Process.respond_to?(:fork)

      CLI.shard_count(requested)
    end

    # engine is the path of a Spinel build of spinel/testbench.rb to run
    # the tests on, one build process per shard, instead of forking.
    def initialize(tests, results_path, shards: 1, resume: false, engine: nil)
      @tests = tests
      @engine = engine
      @results_path = results_path
      @progress = Progress.new("#{results_path}.progress")
      @resume = resume
      @shards = shards
      @results = []
    end

    def run
      FileUtils.mkdir_p([ARTIFACT_DIR, File.dirname(@results_path)])
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pending = pending_tests
      if @engine
        run_engines(pending)
      elsif [@shards, pending.length].min > 1
        run_sharded(pending)
      else
        pending.each { |test| run_one(test) }
      end
      @results = collect
      summarize
      @results.count { |_, result| result != "PASS" }
    end

    private

    # Without --resume a run starts over, so rows an earlier run left
    # behind can't stand in for tests this one never ran.
    def pending_tests
      @progress.clear unless @resume
      finished = @progress.rows
      pending = @tests.reject { |test| finished.key?(test.key) }
      puts "Resuming: #{@tests.length - pending.length} rows from #{@progress.path}." if @resume
      pending
    end

    # Each child owns a disjoint slice of the testlist and appends its rows
    # to the progress file. A child that dies partway would silently
    # shorten the results, so the exit statuses are checked here and the
    # row count in collect.
    def run_sharded(tests)
      groups = Shards.split(tests, [@shards, tests.length].min)
      $stdout.flush
      crashed = forwarding_signals do
        groups.each_with_index { |group, n| @shard_pids << fork { shard(group, n) } }
        forward(@interrupted) if @interrupted
        Process.waitall.count { |_, status| !status.success? }
      end
      raise "#{crashed} of #{groups.length} testbench shards crashed." if crashed.positive?
    end

    # TERM or INT to the runner is passed on to every shard, so stopping
    # the runner's PID stops the whole run instead of orphaning the shards.
    # The shards are reaped before Interrupted is raised, and no results
    # are written. A signal that lands between a fork and its PID being
    # recorded is forwarded again once every shard has started.
    def forwarding_signals
      @shard_pids = []
      runner = Process.pid
      previous = FORWARDED_SIGNALS.to_h do |signal|
        [signal, trap(signal) { forward(signal) if Process.pid == runner }]
      end
      yield.tap { raise Interrupted.new(@interrupted, @progress.path) if @interrupted }
    ensure
      previous&.each { |signal, handler| trap(signal, handler) }
    end

    def forward(signal)
      @interrupted ||= signal
      @shard_pids.each do |pid|
        Process.kill(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    # Each shard's tests run on a build process of their own, read by a
    # thread here that scores each test as its record comes in. Stopping
    # the runner stops the builds, whose unfinished tests get no row.
    def run_engines(tests)
      groups = Shards.split(tests, [@shards, tests.length].min)
      lock = Mutex.new
      forwarding_signals do
        groups.each_with_index.map do |group, n|
          Thread.new { run_engine(group, "#{@results_path}.engine-#{n}", lock) }
        end.each(&:join)
      end
    end

    def run_engine(group, list, lock)
      spawned = lambda do |pid|
        @shard_pids << pid
        forward(@interrupted) if @interrupted
      end
      engine = Engine.new(@engine, list, spawned:, stopped: -> { @interrupted })
      engine.run(group) do |test, outcome, elapsed|
        result = outcome.is_a?(Engine::Outcome) ? score(test, outcome.exit_code, outcome.screen) : outcome
        lock.synchronize do
          @progress.append(test, result)
          report(test, result, elapsed)
        end
      end
    end

    def shard(group, number)
      FORWARDED_SIGNALS.each { |signal| trap(signal, "DEFAULT") }
      group.each { |test| run_one(test) }
      exit!(0)
    rescue StandardError, SystemStackError => e
      warn "shard #{number}: #{e.class}: #{e.message}"
      exit!(1)
    end

    # Every test's row, finished in this run or resumed, in testlist order.
    def collect
      rows = @progress.rows
      results = @tests.filter_map { |test| [test, rows[test.key]] if rows.key?(test.key) }
      return results if results.length == @tests.length

      raise "#{@progress.path} has #{results.length} of #{@tests.length} rows."
    end

    def run_one(test)
      result, elapsed = timed { in_child(test) }
      @progress.append(test, result)
      report(test, result, elapsed)
    end

    # Each test runs in a child forked from a machine this process booted
    # once (see ForkedBoot).
    def in_child(test)
      booted(test).run(test.deadline) { |computer| run_test(test, computer) }
    end

    # A cartridge test starts from power-on, so its machine is never booted:
    # one that loads a program boots in the child, with the cartridge in.
    # A drive test's machine boots with the drive. Each pair of CIA and
    # VIC-II models, each video standard and each expansion gets a machine
    # of its own, and so does each VIC-20 RAM configuration.
    def booted(test)
      @machines ||= {}
      cartridge = !test.cartridge.nil?
      key = [cartridge, test.drive?, *test.models, test.region, test.expansion, *test.family_key]
      @machines[key] ||= ForkedBoot.new(FORWARDED_SIGNALS) do
        next test.family_machine if test.family

        if test.drive?
          Testbench.drive_machine(test.cia_model, test.vic_model)
        else
          Testbench.machine(cartridge, test.cia_model, test.vic_model, test.expansion, region: test.region)
        end
      end
    end

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [yield, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end

    def run_test(test, computer)
      return score(test, *test.run_vic20(computer)) if test.vic20?

      Dir.mktmpdir("testbench-disk") do |scratch|
        exitcode = test.type == "exitcode"
        cartridge = test.cartridge_path if test.cartridge
        Testbench.insert_disk(computer, scratch_disk(test, scratch)) if test.disk
        execution = Execution.new(computer, mount: !test.drive?, load_name: test.load_name)
        exit_code = execution.run(!exitcode, cartridge, test.dir_abs, test.prg, test.budget)
        score(test, exit_code, exitcode ? Testbench.screen_text(computer.ram) : Testbench.screenshot(computer.vic))
      end
    end

    # The drive writes back to the disk image, so a test gets a copy of its
    # own in +scratch+, and the testprogs' image is never written.
    def scratch_disk(test, scratch)
      FileUtils.cp(test.disk_path, scratch)
      File.join(scratch, File.basename(test.disk_path))
    end

    # screen is the text screen for an exitcode test, and the display's
    # rows of palette indices for a screenshot test.
    def score(test, exit_code, screen)
      return score_screenshot(test, exit_code, Screenshot.new(screen)) unless test.type == "exitcode"

      score_exitcode(test, exit_code).tap do |result|
        write_screen(test, screen) unless result == "PASS"
      end
    end

    def score_exitcode(test, exit_code)
      return "PASS" if test.satisfied_by?(exit_code)

      detail = "exit=#{format_code(exit_code)}"
      test.expects == :success ? detail : "#{detail} want=#{test.expects}"
    end

    # An exitcode test prints what went wrong — the failing subtest, and
    # the reference and measured values — which the exit code alone does
    # not carry, so a failure keeps the text screen alongside it.
    def write_screen(test, lines)
      File.write(File.join(ARTIFACT_DIR, "#{test.key.tr('/', '-')}.screen.txt"),
                 "#{lines.join("\n")}\n")
    end

    def score_screenshot(test, exit_code, screenshot)
      return "no-ref" unless File.exist?(test.reference)

      diff = screenshot.compare(test)
      return "ref-size" if diff == :ref_size
      # As in VICE, expect:error on a screenshot test wants a mismatch.
      return diff.positive? ? "PASS" : "diff=0px want=error" if test.expects == :error
      return "PASS" if diff.zero?

      "diff=#{diff}px exit=#{format_code(exit_code)}"
    end

    def format_code(exit_code)
      exit_code ? format("$%02x", exit_code) : "none"
    end

    def report(test, result, elapsed)
      puts format("%-55<id>s %7.1<elapsed>fs %<result>s",
                  id: test.key, elapsed:, result:)
      $stdout.flush
    end

    def summarize
      passed = @results.count { |_, result| result == "PASS" }
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
      puts format("%<passed>d/%<total>d passed in %<wall>.1f min",
                  passed:, total: @results.length, wall: wall / 60)
      File.write(@results_path,
                 @results.map { |test, result| "#{test.key}\t#{Testbench.verdict(result)}" }.join)
      @progress.clear
    end
  end
end

require "fileutils"

module Testbench
  # bin/testbench's command line, returning the exit status.
  def self.main(argv)
    list_only = argv.delete("--list")
    resume = argv.delete("--resume")
    results_path = CLI.take_option(argv, "--results") || File.join(ARTIFACT_DIR, "results.txt")
    scope = CLI.take_option(argv, "--scope")
    exclude = CLI.take_option(argv, "--exclude")
    rows = command_line_rows(argv)
    machine = command_line_machine(argv)
    engine = CLI.take_option(argv, "--engine")
    shards = Runner.shard_count(CLI.take_option(argv, "--shards"))
    tests = command_line_tests(argv, machine, rows, scope:, exclude:)

    unmatched = Testlist.unmatched(argv, tests)
    unless unmatched.empty?
      warn "No test in #{scope || 'the testlist'} matches #{unmatched.join(', ')}."
      return 2
    end

    if list_only
      tests.each { |test| puts "#{test.key} (#{test.type}, #{test.timeout})" }
      puts "#{tests.length} tests"
      return 0
    end

    run_tests(tests, results_path, drive: rows.drive, shards:, resume:, engine:)
  end

  def self.run_tests(tests, results_path, drive:, **)
    if drive && !dos_rom?
      warn "--drive needs the 1541 DOS ROM: #{File.join(Badline.rom_path, DOS_ROM)}."
      return 1
    end

    failures = Runner.new(tests, results_path, **).run
    failures.zero? ? 0 : 1
  rescue Interrupted => e
    warn e.message
    128 + Signal.list.fetch(e.signal)
  end

  def self.command_line_rows(argv)
    models = command_line_models(argv)
    drive = if argv.delete("--1541-testsuite") then :testsuite
            elsif argv.delete("--drive") then :drive
            end
    standard = if argv.delete("--ntsc") then :ntsc
               elsif argv.delete("--drean") then :drean
               else :pal
               end
    Rows.new(carts: !argv.delete("--carts").nil?, models:,
             expansions: !argv.delete("--expansions").nil?, drive:, standard:)
  end

  def self.command_line_models(argv)
    [argv.delete("--cia-new") ? :mos6526a : :mos6526, argv.delete("--vicii-new") ? :mos8565 : :mos6569]
  end

  # :vic20, :c128c64, :c128_z80, :c128 or nil for the C64, deleting every
  # machine flag from argv.
  def self.command_line_machine(argv)
    vic20, c128c64, c128_z80, c128 = %w[--vic20 --c128c64 --c128-z80 --c128].map { |flag| argv.delete(flag) }
    if vic20 then :vic20
    elsif c128c64 then :c128c64
    elsif c128_z80 then :c128_z80
    elsif c128 then :c128
    end
  end

  def self.command_line_tests(argv, machine, rows, scope:, exclude:)
    case machine
    when :vic20 then Vic20Testlist.tests(argv, scope:, exclude:)
    when :c128c64 then C128Testlist.tests(argv, scope:, exclude:)
    when :c128, :c128_z80 then C128ModeTestlist.tests(argv, scope:, exclude:, z80: machine == :c128_z80)
    else Testlist.tests(argv, scope:, exclude:, rows:)
    end
  end
end
