# frozen_string_literal: true

# Running any machine to the cycle its KERNAL has booted by, its
# #init_threshold, where its #on_init handlers run.
module Booting
  module_function

  # Runs +machine+ on to its init threshold and +past+ cycles beyond it,
  # and returns it.
  def boot(machine, past: 0)
    machine.run_cycles(machine.init_threshold + past - machine.cycles)
    machine
  end
end
