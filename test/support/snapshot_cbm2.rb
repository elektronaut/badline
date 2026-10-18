# frozen_string_literal: true

# The CBM-II's scenarios for bin/snapshot_check (SnapshotMachines).
module SnapshotMachines
  CBM2_CRT = File.expand_path("../../vendor/VICE-testprogs/testbench/selftest/cbm610-pass.crt", __dir__)
  CBM2_D82 = File.expand_path("../../vendor/VICE-testprogs/testbench/selftest/cbm610-pass.d82", __dir__)

  # A program that keeps printing the jiffy clock, which scrolls the
  # screen while the mains ticks.
  CBM2_BASIC = "10 print ti;:goto 10\rrun\r"

  # The CBM-II: a 610 running BASIC, a 720 at 60 Hz on 901244-03b part way
  # through its RAM test, while LDA and STA (zp),Y reach the other
  # segments, a 610 with the selftest's cartridge in, and one loading the
  # selftest's program from its .d82 in device 8 through the traps.
  def cbm2_scenarios
    [
      Scenario.new("cbm2-610-basic", :cbm2, ->(_dir) { typing(Badline::CBM2.new, CBM2_BASIC) },
                   ->(m) { run(m, 8_600_001) }),
      Scenario.new("cbm2-720-ramtest", :cbm2, ->(_dir) { Badline::CBM2.new(model: "720", kernal: "03b", mains_hz: 60) },
                   ->(m) { run(m, 3_000_001) }),
      Scenario.new("cbm2-cartridge", :cbm2, lambda { |_dir|
        Badline::CBM2.new.tap { |m| m.attach_cartridge(Badline::Storage::CRTFile.new(CBM2_CRT, machine: :cbm2).chips) }
      }, ->(m) { run(m, 1_000_001) }),
      Scenario.new("cbm2-traps-d82", :cbm2, ->(dir) { attached(Badline::CBM2.new, copy(CBM2_D82, dir)) },
                   ->(m) { run(m, 8_400_001) })
    ]
  end

  module_function :cbm2_scenarios
end
