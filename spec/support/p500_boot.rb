# frozen_string_literal: true

require_relative "taken_once"

# P500s booted to READY once for every spec that reads them, kept as a
# snapshot taken once, which each spec loads into a machine of its own.
module P500Boot
  # A new machine of +model+, restored from the snapshot taken once it
  # booted.
  def booted(model = "510") = TakenOnce.fetch([:p500_booted_image, model]) { boot(model).snapshot }.load

  def boot(model)
    machine = Badline::CBM2::P500.new(model:)
    machine.run_cycles(machine.init_threshold)
    machine
  end

  # The text screen's lines in the static video matrix at $D000 of
  # segment 15, the empty ones left out.
  def screen_lines(machine)
    Array.new(25) do |row|
      Array.new(40) do |column|
        code = machine.bus.peek_bank(15, 0xd000 + (row * 40) + column) & 0x7f
        (code < 0x20 ? code + 0x60 : code).chr
      end.join.rstrip
    end.reject(&:empty?)
  end
end
