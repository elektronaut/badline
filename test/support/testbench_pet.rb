# frozen_string_literal: true

# Which rows bin/testbench --pet and --pet-discrete run, from
# pet-testlist.in, and the machine each asks for. The machine-driving half
# is in test/support/testbench_pet_machine.rb, which the Spinel build
# shares.
module Testbench
  PET_TESTLIST = File.expand_path("../../vendor/VICE-testprogs/testbench/pet-testlist.in", __dir__)

  # The testlist's machine, as xpet's hook starts it, and the discrete
  # video boards --pet-discrete runs the same rows on.
  PET_MODEL = "8096"
  PET_DISCRETE_MODELS = %w[2001 3032].freeze

  # The option that names a row's model, which only --pet-discrete adds.
  PET_MODEL_OPTION = "pet-model:"

  # A TestCase's machine, when the row is the PET's, and its run.
  module PETRow
    def pet? = family == :pet

    def pet_model
      option = options.find { |candidate| candidate.start_with?(PET_MODEL_OPTION) }
      option ? option.delete_prefix(PET_MODEL_OPTION) : PET_MODEL
    end

    # What a --pet-discrete row's id ends in, as one program runs on each
    # model: @2001 or @3032.
    def model_suffix = pet? && pet_model != PET_MODEL ? "@#{pet_model}" : ""

    def pet_machine = Testbench.pet_machine(pet_model)

    # Runs the row on +machine+, returning the exit code and the text
    # screen, or the picture for a screenshot row.
    def run_pet(machine)
      exit_code = PETExecution.new(machine).run(dir_abs, prg, budget)
      [exit_code, type == "screenshot" ? Testbench.pet_screenshot(machine) : Testbench.pet_screen_text(machine)]
    end
  end

  # A PET screenshot against its reference. VICE's testbench compares the
  # two from (32, 33) on, over the lines and dots both have, and so does
  # this. A reference dot counts as lit where it is more green than not.
  class PETScreenshot
    LEFT = 32
    TOP = 33

    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    # The number of mismatched dots.
    def compare(test)
      png = ChunkyPNG::Image.from_file(test.reference)
      width = [png.width, rows.first.length].min
      diff = 0
      (TOP...[png.height, rows.length].min).each do |y|
        row = rows[y]
        (LEFT...width).each { |x| diff += 1 unless (ChunkyPNG::Color.g(png[x, y]) > 0x80 ? 1 : 0) == row[x] }
      end
      write_actual(test) if diff.positive?
      diff
    end

    private

    def write_actual(test)
      png = ChunkyPNG::Image.new(rows.first.length, rows.length)
      rows.each_with_index do |row, y|
        row.each_with_index do |index, x|
          color = Badline::PET::Canvas::PALETTE[index]
          png[x, y] = ChunkyPNG::Color.rgb(color >> 16, (color >> 8) & 0xff, color & 0xff)
        end
      end
      png.save(File.join(ARTIFACT_DIR, "#{test.key.tr('/', '-')}.actual.png"))
    end
  end

  # The PET testlist's exitcode and screenshot rows on the 8096, or its
  # exitcode rows with +discrete+ on each of PET_DISCRETE_MODELS, as the
  # references show an 8096's screen. Interactive rows are left out as on
  # the C64.
  module PETTestlist
    module_function

    def tests(filters, discrete: false, scope: nil, exclude: nil)
      models = discrete ? PET_DISCRETE_MODELS : [nil]
      rows = File.readlines(PET_TESTLIST).flat_map { |line| models.filter_map { |model| parse(line, model) } }
      Testlist.numbered(rows).select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, model = nil)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless type == "exitcode" || (type == "screenshot" && model.nil?)

      options << "#{PET_MODEL_OPTION}#{model}" if model
      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, nil)
      test.family = :pet
      test if File.exist?(File.join(test.dir_abs, test.prg))
    end
  end
end
