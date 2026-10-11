# frozen_string_literal: true

require "badline/core"
require "badline/plus4"

# The 264 series' tape scenarios: a program saved to the datasette and
# loaded back through the KERNAL's tape routines, which time the read
# line's half waves with the TED's timers, on a Plus/4 and on a C16, whose
# cassette sense has no 6529 to go through.
module DriveScenarios
  module Plus4TapeRuns
    CHECKS = {
      "plus4-tape" => %w[saves loads-back],
      "plus4-c16-tape" => %w[saves loads-back]
    }.freeze

    module_function

    # SAVE to a blank tape with RECORD and PLAY down, then rewind it, and
    # NEW, LOAD and LIST with PLAY down.
    def run(report, dir, model)
      machine = Badline::Plus4.new(model:)
      datasette = machine.datasette
      datasette.insert(Badline::Storage::TAP.create(File.join(dir, "#{model}-tape.tap"), platform: 2))
      output = machine.capture_output
      machine.on_init { machine.type_text("10 print\"hello\"\rsave\"test\"\r") }
      Runs.run_until(machine, 5_000_000) { output.output.upcase.include?("RECORD ON TAPE") }
      datasette.record!
      Runs.run_until(machine, 60_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      datasette.stop!
      report.check("saves", output.output.upcase.include?("SAVING TEST"), "printed no SAVING TEST")
      datasette.rewind
      datasette.play!
      machine.type_text("new\rload\rlist\r")
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= 5 }
      text = output.output.upcase
      report.check("loads-back", text.include?("FOUND TEST") && text.include?("10 PRINT\"HELLO\""),
                   "printed no FOUND TEST and 10 PRINT\"HELLO\"")
    end
  end
end
