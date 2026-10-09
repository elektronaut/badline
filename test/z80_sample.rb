# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "tmpdir"

# The first cases of every SingleStepTests Z80 file, fetched without the
# rest of the suite. A blobless clone lists the files, and an HTTP range
# request per file reads only as many bytes as those cases take. Each file
# is one line of JSON, so the cases are cut at the start of the one after
# the last case wanted.
module Z80Sample
  REPO = "SingleStepTests/z80"
  COMMIT = "ebe1875d48f374bcfd4b505d8eb8ee751568b5f7"
  CASES = 100
  DIR = "vendor/z80-sample"
  THREADS = 8

  module_function

  def fetch(dir = DIR)
    names = list_files
    tmp = "#{dir}.tmp"
    FileUtils.rm_rf(tmp)
    FileUtils.mkdir_p(File.join(tmp, "v1"))
    queue = Queue.new
    names.each { |name| queue << name }
    Array.new(THREADS) { Thread.new { fetch_queued(queue, tmp) } }.each(&:join)
    FileUtils.rm_rf(dir)
    FileUtils.mv(tmp, dir)
  end

  def list_files
    Dir.mktmpdir do |clone|
      system("git", "init", "--quiet", clone, exception: true)
      git(clone, "fetch", "--quiet", "--depth", "1", "--filter=blob:none", "https://github.com/#{REPO}", COMMIT)
      git(clone, "ls-tree", "--name-only", "FETCH_HEAD", "v1/").lines(chomp: true).grep(/\.json\z/)
    end
  end

  def git(dir, *args)
    out, status = Open3.capture2("git", "-C", dir, *args)
    raise "git #{args.first} failed" unless status.success?

    out
  end

  def fetch_queued(queue, dir)
    Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true) do |http|
      loop do
        name = queue.pop(true)
        File.write(File.join(dir, name), head(http, "/#{REPO}/#{COMMIT}/#{name.gsub(' ', '%20')}"))
      end
    rescue ThreadError
      nil
    end
  end

  # The JSON array of the file's first CASES cases, reading twice as far
  # each time the bytes read so far hold fewer.
  def head(http, path, length = 1 << 17)
    response = http.get(path, "Range" => "bytes=0-#{length - 1}")
    raise "#{path}: HTTP #{response.code}" unless %w[200 206].include?(response.code)

    body = response.body
    cut = case_start(body, CASES)
    return "#{body[0...(cut - 1)]}]" if cut
    return body if response.code == "200" || body.bytesize < length

    head(http, path, length * 2)
  end

  def case_start(body, index)
    position = 0
    index.times do
      position = body.index('},{"name":', position)
      return unless position

      position += 2
    end
    position
  end
end
