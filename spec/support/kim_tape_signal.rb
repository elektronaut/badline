# frozen_string_literal: true

# KIM-1 tape signals made up for specs (User Manual, appendix E): a block
# as characters, the crossings of the square wave that carries them, a
# recording of it as samples, and a .wav file of those. Bits go out LSB
# first, each a run of 3,700 Hz periods then a run of 2,400 Hz ones.
module KIMTapeSignal
  HIGH_TONE = 135
  LOW_TONE = 208

  # The periods of each tone in a 0 and in a 1: DUMPT's, and a third of
  # them, the speed of Hypertape and of the archive's recordings.
  ROM_SPEED = { 0 => [18, 6], 1 => [9, 12] }.freeze
  FAST = { 0 => [6, 2], 1 => [3, 4] }.freeze

  module_function

  def hex(byte) = format("%02X", byte).bytes

  # A block as LOADT ($1873) reads it: SYN characters, of which LOADT
  # wants 11 in a row, *, the ID, the address and the bytes in hex, /, the
  # checksum of the address and the bytes, and two EOTs.
  def block(id, address, bytes, syn: 16)
    low = address & 0xff
    high = address >> 8
    checksum = (low + high + bytes.sum) & 0xffff
    ([0x16] * syn) + [0x2a] + hex(id) + hex(low) + hex(high) + bytes.flat_map { |byte| hex(byte) } +
      [0x2f] + hex(checksum & 0xff) + hex(checksum >> 8) + [0x04, 0x04]
  end

  # The crossings of `chars` as a square wave from `start` microseconds.
  def crossings(chars, speed: FAST, start: 1_000)
    times = []
    time = start
    chars.each do |char|
      8.times do |bit|
        high, low = speed.fetch((char >> bit) & 1)
        [[high, HIGH_TONE], [low, LOW_TONE]].each do |periods, half|
          (periods * 2).times { times << (time += half) }
        end
      end
    end
    times
  end

  # `crossings` recorded at `rate`, as a cassette might give them back: a
  # half sine between each two crossings, scaled by `gain` and lifted by
  # `offset`, with noise of up to `noise`.
  def samples(crossings, rate: 22_050, gain: 0.8, offset: 0.0, noise: 0.0)
    random = Random.new(1)
    index = 0
    Array.new(((crossings.last + 1_000) * rate) / 1_000_000) do |n|
      time = n * 1_000_000.0 / rate
      index += 1 while index < crossings.length && crossings[index] <= time
      wave = 0.0
      if index.positive? && index < crossings.length
        from = crossings[index - 1]
        wave = Math.sin(Math::PI * (time - from) / (crossings[index] - from)) * (index.odd? ? 1 : -1)
      end
      (gain * wave) + offset + (noise * (random.rand - 0.5) * 2)
    end
  end

  # `samples` as a .wav file's bytes, PCM of `bits`, the samples on the
  # first of `channels` and silence on the rest.
  def wav(samples, rate: 22_050, bits: 8, channels: 1)
    size = bits / 8
    data = samples.flat_map do |sample|
      level = sample.clamp(-1.0, 1.0)
      frame = bits == 8 ? [(level * 127).round + 128] : le((level * 32_767).round & 0xffff, 2)
      frame + ((bits == 8 ? [128] : [0, 0]) * (channels - 1))
    end
    "RIFF".bytes + le(36 + data.length, 4) + "WAVEfmt ".bytes + le(16, 4) + le(1, 2) + le(channels, 2) +
      le(rate, 4) + le(rate * channels * size, 4) + le(channels * size, 2) + le(bits, 2) +
      "data".bytes + le(data.length, 4) + data
  end

  def le(value, count) = Array.new(count) { |i| (value >> (8 * i)) & 0xff }

  # The characters in PB7's `edges` as LOADT's RDBIT ($1A41) tells the
  # bits, each a 1 where PB7 is high for longer than it was low, from the
  # first SYN on.
  def characters(edges)
    bits = edges.each_slice(2).each_cons(2).map do |(fell, rose), (next_fell, _)|
      next_fell - rose > rose - fell ? 1 : 0
    end
    start = (0..(bits.length - 8)).find { |i| value(bits, i) == 0x16 }
    return [] if start.nil?

    bits[start..].each_slice(8).select { |byte| byte.length == 8 }.map { |byte| value(byte, 0) }
  end

  def value(bits, from) = Array.new(8) { |bit| bits[from + bit] << bit }.sum
end
