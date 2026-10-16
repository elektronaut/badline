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
    # screen.
    def run_pet(machine)
      [PETExecution.new(machine).run(dir_abs, prg, budget), Testbench.pet_screen_text(machine)]
    end
  end

  # The PET testlist's exitcode rows, on the 8096, or with +discrete+ on
  # each of PET_DISCRETE_MODELS. Screenshot rows wait for the video, and
  # interactive rows are left out as on the C64.
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
      return unless type == "exitcode"

      options << "#{PET_MODEL_OPTION}#{model}" if model
      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, nil)
      test.family = :pet
      test if File.exist?(File.join(test.dir_abs, test.prg))
    end
  end
end
