# frozen_string_literal: true

# Converts the first cases of each SingleStepTests Z80 file into a line
# format the Spinel harness can parse without a JSON library:
#
#   ruby -Ilib spinel/convert_z80.rb [cases_per_file] [out]
#
# The registers are listed in Z80Tests::REGISTERS' order. Ports are
# address, value and kind (0 read, 1 write), and the pins of each T-state
# are the address, the data or -1, and the lines as a mask (Z80Tests::PINS).
require_relative "../test/support/z80_single_step"

REGISTERS = %w[a f b c d e h l i r pc sp ix iy wz im q af_ bc_ de_ hl_ iff1 iff2 ei p].freeze
PINS = { "r" => 1, "w" => 2, "m" => 4, "i" => 8 }.freeze

def pins(cycles)
  cycles.map do |address, data, lines|
    "#{address} #{data || -1} #{lines.chars.sum { |line| PINS.fetch(line, 0) }}"
  end.join(" ")
end

per = (ARGV[0] || 20).to_i
File.open(ARGV[1] || "tmp/spinel/z80_cases.txt", "w") do |out|
  Z80SingleStep.files.sort.each do |path|
    Z80SingleStep.cases(path).first(per).each do |t|
      out.puts "T #{t['name']}"
      out.puts "I #{REGISTERS.map { |k| t['initial'][k] }.join(' ')}"
      out.puts "R #{t['initial']['ram'].flatten.join(' ')}"
      out.puts "P #{t.fetch('ports', []).map { |a, v, k| "#{a} #{v} #{k == 'r' ? 0 : 1}" }.join(' ')}"
      out.puts "F #{REGISTERS.map { |k| t['final'][k] }.join(' ')}"
      out.puts "M #{t['final']['ram'].flatten.join(' ')}"
      out.puts "C #{pins(t['cycles'])}"
    end
  end
end
