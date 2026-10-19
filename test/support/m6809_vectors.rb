# frozen_string_literal: true

require "fileutils"
require "net/http"
require_relative "moo_reader"

# neetandev/m6809's single-step vectors for the MC6809, 1,000 cases per
# opcode, which MAME's 6809 generated as data. The data is MIT-0
# (v1/LICENSE). The repository also carries the generator, and in
# testgen/mame the GPL source it runs, so nothing here clones it or takes
# an archive of it: each file is a raw download at COMMIT, and every path
# is built under v1/ from the names v1/manifest.txt lists.
module M6809Vectors
  REPO = "neetandev/m6809"
  COMMIT = "9dd7b59284ecc2667268149dbad049e91e36cc9e"
  DIR = "vendor/m6809"
  FILES = %w[manifest.txt metadata.json LICENSE].freeze
  THREADS = 8

  # The order of the registers in a REGS chunk's mask.
  REGISTERS = %i[pc s u x y dp a b cc].freeze

  module_function

  def fetch(dir = DIR)
    tmp = "#{dir}.tmp"
    FileUtils.rm_rf(tmp)
    FileUtils.mkdir_p(File.join(tmp, "v1"))
    Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true) do |http|
      FILES.each { |name| File.binwrite(File.join(tmp, "v1", name), download(http, name)) }
    end
    queue = Thread::Queue.new
    manifest(tmp).each_key { |stem| queue << "#{stem}.moo.gz" }
    Array.new(THREADS) { Thread.new { fetch_queued(queue, tmp) } }.each(&:join)
    check(tmp)
    FileUtils.rm_rf(dir)
    FileUtils.mv(tmp, dir)
  end

  def fetch_queued(queue, dir)
    Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true) do |http|
      loop do
        name = queue.pop(true)
        File.binwrite(File.join(dir, "v1", name), download(http, name))
      end
    rescue ThreadError
      nil
    end
  end

  def download(http, name)
    path = "/#{REPO}/#{COMMIT}/v1/#{name.gsub(' ', '%20')}"
    response = http.get(path)
    raise "#{path}: HTTP #{response.code}" unless response.code == "200"

    response.body
  end

  # Each opcode's file stem, such as "3a" or "10 a3", and its case count.
  def manifest(dir = DIR)
    File.readlines(File.join(dir, "v1", "manifest.txt"), chomp: true).to_h do |line|
      stem, count = line.rpartition(" ").values_at(0, 2)
      [stem, Integer(count)]
    end
  end

  def files(dir = DIR) = manifest(dir).keys.map { |stem| path(stem, dir) }

  def path(stem, dir = DIR) = File.join(dir, "v1", "#{stem}.moo.gz")

  def reader(path) = MOOReader.open(path, REGISTERS)

  # Raises unless every file the manifest lists holds its count of cases.
  def check(dir = DIR)
    wrong = manifest(dir).reject do |stem, count|
      file = reader(path(stem, dir))
      file.count == count && file.chunks == count
    end
    raise "#{wrong.keys.join(', ')}: not the manifest's case count" if wrong.any?
  end
end
