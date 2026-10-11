# frozen_string_literal: true

# Runs the Wolfgang Lorenz suite's plus4 build on a PAL Plus/4 with the
# same driver as bin/lorenz --plus4 (test/support/lorenz_chain.rb) and
# prints what the run recorded, as spinel/lorenz.rb does for the C64.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/plus4_lorenz.rb image [--resume NAME] [--stop-after NAME]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/plus4_lorenz.rb -o tmp/spinel/plus4_lorenz

require "badline/core"
require "badline/plus4"
require_relative "../test/support/lorenz_chain"

module Lorenz
  # Runs the chain on a fresh Plus/4 and returns what it recorded. An
  # empty resume starts the chain from the top, and an empty stop_after
  # runs it to the end.
  def self.run_plus4_chain(image, resume, stop_after, max_cycles)
    computer = Badline::Plus4.new
    computer.ted.render = false
    capture = computer.capture_output
    disk = mount(computer, image, capture, (resume unless resume.empty?), PLUS4_NEXT_DISK)
    chain = Chain.new(computer, capture, disk, max_cycles, (stop_after unless stop_after.empty?))
    chain.key_limit = PLUS4_KEY_LIMIT
    chain.test_cycle_limit = PLUS4_TEST_CYCLE_LIMIT
    chain.step until chain.result

    out = +""
    offsets = disk.offsets
    disk.names.each_with_index { |name, index| out << "load #{offsets[index]} #{name}\n" }
    chain.key_offsets.each { |offset| out << "key #{offset}\n" }
    out << "result #{chain.result} #{computer.cycles}\n"
    out << "transcript #{capture.output.length}\n"
    out << capture.output
  end
end

image = ""
resume = ""
stop_after = ""
i = 0
while i < ARGV.length
  case ARGV[i]
  when "--resume"
    resume = ARGV[i + 1]
    i += 1
  when "--stop-after"
    stop_after = ARGV[i + 1]
    i += 1
  else
    image = ARGV[i]
  end
  i += 1
end
raise "Usage: plus4_lorenz image [--resume NAME] [--stop-after NAME]" if image.empty?

print Lorenz.run_plus4_chain(image, resume, stop_after, 10_000_000_000)
