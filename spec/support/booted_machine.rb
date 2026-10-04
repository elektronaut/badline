# frozen_string_literal: true

# A machine booted to BASIC's prompt, for specs that start from there.
module BootedMachine
  # The booted machine's State, taken once for every spec that restores it.
  def self.state
    @state ||= Badline::Computer.new.tap { |computer| 2_600_000.times { computer.cycle! } }.snapshot
  end

  # A new machine at BASIC's prompt, restored from the shared State.
  def booted = Badline::Computer.restored(BootedMachine.state)
end
