# frozen_string_literal: true

# Converts the first cases of each neetandev/m6809 file into a line format
# the Spinel harness can parse without a MOO reader:
#
#   ruby -Ilib spinel/convert_m6809.rb [cases_per_file] [out]
#
# The registers are in M6809Vectors::REGISTERS' order. Each cycle of the
# trace is a kind (0 none, 1 read, 2 write), an address and the data, -1
# where it isn't checked. The final registers and the trace are what
# M6809Divergences expects where the documents and the vectors disagree.
require_relative "../test/support/m6809_single_step"

KINDS = { "----" => 0, "r-m-" => 1, "-wm-" => 2 }.freeze

def registers(values) = M6809Vectors::REGISTERS.map { |name| values.fetch(name) }.join(" ")

def trace(test)
  M6809Divergences.expected_trace(test).map do |status, address, data|
    "#{KINDS.fetch(status)} #{address} #{data || -1}"
  end
end

per = (ARGV[0] || 20).to_i
File.open(ARGV[1] || "tmp/spinel/m6809_cases.txt", "w") do |out|
  M6809Vectors.files.each do |path|
    M6809Vectors.reader(path).first(per).each do |test|
      out.puts "T #{test.name.tr(' ', '_')}"
      out.puts "I #{registers(test.initial.registers)}"
      out.puts "R #{test.initial.ram.flatten.join(' ')}"
      out.puts "F #{registers(M6809Divergences.expected_registers(test))}"
      out.puts "M #{test.final.ram.flatten.join(' ')}"
      out.puts "C #{trace(test).join(' ')}"
    end
  end
end
