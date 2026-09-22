# frozen_string_literal: true

# Replays one cell of Lorenz's cia1ta/cia1tb against a bare CIA, cycle by
# cycle. Offsets count from the latch-low write that starts the cell. Each
# access lands on the last cycle of an absolute instruction, after the CIA
# has ticked for that cycle.
module CiaTimerReplay
  REGISTERS = { a: [0x04, 0x0e, 0x81], b: [0x06, 0x0f, 0x82] }.freeze

  module_function

  # [counter low, ICR, control]
  def run(timer, init, init_control, before, before_control)
    latch_low, control, mask = REGISTERS.fetch(timer)
    cia = Badline::CIA.new
    # The loop's writes ahead of the cell: every IRQ off but the timer's,
    # timer stopped, latch high cleared
    [[0x0d, 0x7f], [0x0d, mask], [control, 0x00], [latch_low + 1, 0x00]].each do |register, value|
      access(cia, 4, :poke, register, value)
    end
    access(cia, 8, :poke, latch_low, init)       # 0
    access(cia, 6, :poke, control, 0x10)         # 6
    access(cia, 4, :peek, 0x0d)                  # 10
    access(cia, 4, :poke, control, init_control) # 14
    access(cia, 8, :poke, latch_low, before)     # 22
    access(cia, 4, :poke, control, before_control) # 26
    [access(cia, 4, :peek, latch_low), access(cia, 4, :peek, 0x0d), access(cia, 4, :peek, control)] # 30, 34, 38
  end

  def access(cia, cycles, method, *)
    cycles.times { cia.cycle! }
    cia.public_send(method, *)
  end
end
