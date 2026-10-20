# frozen_string_literal: true

# The KIM-1's scenarios for bin/snapshot_check (SnapshotMachines).
module SnapshotMachines
  # LDA #$40, STA $170D: U3's timer at ÷8 with its interrupt on, then CLI
  # and a loop counting at $10, and at $0210 the interrupt's handler,
  # which counts at $11 and starts the timer again.
  KIM1_TIMER_PROGRAM = {
    0x0200 => [0xa9, 0x40, 0x8d, 0x0d, 0x17, 0x58, 0xe6, 0x10, 0x4c, 0x06, 0x02],
    0x0210 => [0xe6, 0x11, 0xa9, 0x40, 0x8d, 0x0d, 0x17, 0x40],
    0x17fe => [0x10, 0x02]
  }.freeze

  # The KIM-1: its monitor on the keypad, saved with a key held down part
  # way through the keys typed, a program counting on U3's timer's
  # interrupt, wired to IRQ, the monitor on a teletype, saved with a
  # character on its way in, on an expanded board, and LOADT part way
  # through a tape's leader.
  def kim1_scenarios
    [
      Scenario.new("kim1-keypad", :kim1, ->(_dir) { typing(Badline::KIM1.new, "AD 0200 DA A9 + 01") },
                   ->(m) { run(m, 70_001) }),
      Scenario.new("kim1-timer", :kim1, ->(_dir) { kim1_timer }, ->(m) { run(m, 160_001) }),
      Scenario.new("kim1-tty", :kim1, ->(_dir) { typing(Badline::KIM1.new(tty: true, ram: :expanded), "0200 ") },
                   ->(m) { run(m, 15_001) }),
      Scenario.new("kim1-tape", :kim1, ->(_dir) { kim1_tape }, ->(m) { run(m, 200_001) })
    ]
  end

  # A KIM-1 in LOADT, with a tape of SYN characters playing: 3,700 Hz for
  # two thirds of each 0 and 2,400 Hz for a third, and the other way round
  # for each 1, 135 and 208 microseconds a half period.
  def kim1_tape
    halves = ([0x16] * 40).flat_map do |char|
      Array.new(8) { |bit| char[bit] }.flat_map do |bit|
        ([135] * (bit.zero? ? 12 : 6)) + ([208] * (bit.zero? ? 4 : 8))
      end
    end
    time = 1_000
    crossings = halves.map { |half| time += half }
    machine = Badline::KIM1.new
    machine.tape.insert_tape(Badline::Storage::KIMTape.new(crossings:))
    machine.tape.play
    typing(machine, "AD 1873 GO")
  end

  def kim1_timer
    machine = Badline::KIM1.new
    machine.irq_wired = true
    KIM1_TIMER_PROGRAM.each do |address, bytes|
      bytes.each_with_index { |byte, offset| machine.poke(address + offset, byte) }
    end
    typing(machine, "AD 0200 GO")
  end

  module_function :kim1_scenarios, :kim1_timer, :kim1_tape
end
