# frozen_string_literal: true

# Converts a sample of SingleStepTests JSON into a line format the Spinel
# harness can parse without a JSON library:
#
#   ruby -Ilib spinel/convert.rb [cases_per_opcode] [out]
require "json"
require "badline"

per = (ARGV[0] || 100).to_i
rng = Random.new(1)
File.open(ARGV[1] || "tmp/spinel/cases.txt", "w") do |out|
  Badline::Instruction.map.keys.sort.each do |opcode|
    tests = JSON.parse(File.read(format("vendor/65x02/6502/v1/%02x.json", opcode)))
    tests.sample(per, random: rng).each do |t|
      i = t["initial"]
      f = t["final"]
      out.puts "T #{t['name']}"
      out.puts "I #{%w[pc s a x y p].map { |k| i[k] }.join(' ')}"
      out.puts "R #{i['ram'].flatten.join(' ')}"
      out.puts "F #{%w[pc s a x y p].map { |k| f[k] }.join(' ')}"
      out.puts "M #{f['ram'].flatten.join(' ')}"
      out.puts "C #{t['cycles'].map { |a, v, k| "#{a} #{v} #{k == 'read' ? 0 : 1}" }.join(' ')}"
    end
  end
end
