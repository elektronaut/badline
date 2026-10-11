# frozen_string_literal: true

require "json"
require "open3"
require_relative "ci_matrix"

# The scheduled suites run in .github/workflows/suites.yml: whether a tick
# has anything to run, the `suites` commit status it leaves, and the one
# issue labelled suites-red that names what moved while main is red. Also
# what release.yml waits on before it publishes a tag. bin/suites_status is
# its command line.
module SuitesStatus
  CONTEXT = "suites"
  LABEL = "suites-red"
  WORKFLOW = "suites.yml"
  FINAL = %w[success failure error].freeze
  FAILED = %w[failure timed_out startup_failure].freeze
  # How far back on main's first-parent history to look for the last green
  # run before giving up on naming a range.
  GREEN_SEARCH = 100

  # The REST API through the gh command line, which reads GH_TOKEN.
  class GitHub
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def get(path)
      JSON.parse(gh("api", path))
    end

    # Every page of a list, or of the array under key in an object.
    def get_all(path, key = nil)
      pages = JSON.parse(gh("api", "--paginate", "--slurp", path))
      key ? pages.flat_map { |page| page.fetch(key) } : pages.flatten(1)
    end

    def post(path, body) = send_json("POST", path, body)

    def patch(path, body) = send_json("PATCH", path, body)

    private

    def send_json(method, path, body)
      output = gh("api", "--method", method, path, "--input", "-", stdin_data: JSON.generate(body))
      output.strip.empty? ? nil : JSON.parse(output)
    end

    def gh(*args, stdin_data: "")
      output, error, status = Open3.capture3("gh", *args, stdin_data:)
      raise "gh #{args.join(' ')} failed: #{error.strip}" unless status.success?

      output
    end
  end

  # One moved row, as Regression::Comparison#publish records it for the
  # comparison named name: spinel-testbench-cia, sid or spinel-lorenz-1.
  Moved = Data.define(:shard, :name, :key, :before, :after) do
    def suite
      plain = name.delete_prefix("spinel-")
      Suites::ALL_SUITES.key?(plain) ? plain : plain.sub(/-\d+\z/, "")
    end

    def to_markdown = "- `#{key}`: `#{before}` → `#{after}`"
  end

  # What a finished run found: the jobs that failed or were cancelled, and
  # the rows each shard reported moved.
  class Verdict
    attr_reader :moved

    # jobs as the API lists a run's jobs. moved_dir holds a moved-<shard>
    # directory for each shard that recorded moved rows.
    def initialize(jobs, moved_dir)
      @jobs = jobs
      @moved = read_moved(moved_dir)
    end

    def state
      return "failure" if failed.any?
      return "error" if @jobs.any? { |job| job["conclusion"] == "cancelled" }

      "success"
    end

    def description
      case state
      when "success" then "Every suite matches its baseline"
      when "error" then "The run was cancelled"
      else "#{moved.length} moved row(s), #{failed.length} failed job(s)"
      end
    end

    def failed
      @failed ||= @jobs.select { |job| FAILED.include?(job["conclusion"]) }.map { |job| job.fetch("name") }
    end

    # The failed jobs that recorded no moved rows: a compile error, a crash,
    # a check against CRuby or a stretch that ended short.
    def unexplained
      failed.reject { |job| moved.any? { |row| row.shard == SuitesStatus.shard(job) } }
    end

    # The suites and checks behind the failures, or CIReach::ALL when a job
    # outside the shards failed, such as the harness build.
    def blamed
      shards = unexplained.map { |job| SuitesStatus.shard(job) }
      return CIReach::ALL if shards.include?(nil)

      (moved.map(&:suite) + shards.flat_map { |shard| SuitesStatus.shard_suites(shard) }).uniq.sort
    end

    private

    def read_moved(dir)
      Dir.glob(File.join(dir, "moved-*", "*.jsonl")).flat_map do |path|
        shard = File.basename(File.dirname(path)).delete_prefix("moved-")
        File.readlines(path, chomp: true).reject(&:empty?).map do |line|
          row = JSON.parse(line)
          Moved.new(shard:, name: row.fetch("name"), key: row.fetch("key"), before: row.fetch("before"),
                    after: row.fetch("after"))
        end
      end
    end
  end

  # A merged pull request and the suites its files reach.
  Pull = Data.define(:number, :title, :reach) do
    def reaches?(blamed)
      return true if reach == CIReach::ALL
      return reach.any? if blamed == CIReach::ALL

      reach.intersect?(blamed)
    end

    def to_markdown
      named = reach == CIReach::ALL ? "every suite" : reach.join(", ")
      "- ##{number} #{title} (reaches #{named})"
    end
  end

  # A red run's commit and the history behind it: the last green commit,
  # nil when none was found, and the commits and pull requests since.
  Red = Data.define(:sha, :run_url, :green, :commits, :pulls, :compare_url)

  # The body of the suites-red issue.
  class IssueBody
    def initialize(verdict, red)
      @verdict = verdict
      @sha = red.sha
      @run_url = red.run_url
      @green = red.green
      @commits = red.commits
      @pulls = red.pulls
      @compare_url = red.compare_url
    end

    def title = "Suites red on main at #{@sha[0, 8]}"

    def to_s
      [intro, moved_section, unexplained_section, range_section, pulls_section].compact.join("\n\n") << "\n"
    end

    private

    def intro
      "The scheduled suites run went red at #{@sha} ([run](#{@run_url})). This issue is updated on each " \
        "red run and closed by the next green one."
    end

    def moved_section
      return if @verdict.moved.empty?

      groups = @verdict.moved.group_by { |row| [row.name, row.shard] }.map do |(name, shard), rows|
        ["**#{name}** (shard #{shard})", *rows.map(&:to_markdown)].join("\n")
      end
      ["### Moved rows", *groups].join("\n\n")
    end

    def unexplained_section
      return if @verdict.unexplained.empty?

      jobs = @verdict.unexplained.map { |job| "- #{job}" }
      ["### Failed without a moved row", "A build, crash or check failure. The run's log has it.", *jobs].join("\n")
    end

    def range_section
      return "### Since the last green run\n\nNo green run in the last #{GREEN_SEARCH} commits on main." unless @green

      "### Since the last green run\n\n[#{@green[0, 8]}...#{@sha[0, 8]}](#{@compare_url}), " \
        "#{@commits.length} commit(s) on main's first-parent line."
    end

    def pulls_section
      return unless @green

      blamed = @verdict.blamed
      reaching = @pulls.select { |pull| pull.reaches?(blamed) }
      lines = reaching.empty? ? ["None of the merged pull requests reach them."] : reaching.map(&:to_markdown)
      named = blamed == CIReach::ALL ? "every suite" : blamed.join(", ")
      ["### Pull requests that reach #{named}", *lines].join("\n")
    end
  end

  module_function

  # The shard a job of the suites matrix ran, from its name.
  def shard(job_name) = job_name[/Suites \(([^)]+)\)\z/, 1]

  def shard_suites(shard)
    CIMatrix::SHARDS.fetch(shard, []).map { |entry| Array(entry).first }
  end

  # The newest `suites` status on sha, or nil.
  def status(github, sha)
    github.get("repos/#{github.repo}/commits/#{sha}/statuses?per_page=100").find do |each|
      each["context"] == CONTEXT
    end
  end

  def set_status(github, sha, state, description, target_url)
    github.post("repos/#{github.repo}/statuses/#{sha}",
                { state:, context: CONTEXT, description:, target_url: })
  end

  # Whether a run should go ahead. A scheduled tick skips a commit that
  # already has a status, from an earlier run or one in progress. A run
  # dispatched by hand or by release.yml always goes ahead.
  def start?(github, sha, event)
    event != "schedule" || status(github, sha).nil?
  end

  # The newest commit on sha's first-parent line before it whose suites
  # status is green.
  def last_green(github, history)
    history.find { |sha| status(github, sha)&.fetch("state") == "success" }
  end

  # The pull requests merged in commits, with the suites their files reach.
  def pulls(github, commits)
    numbers = commits.flat_map do |sha|
      github.get("repos/#{github.repo}/commits/#{sha}/pulls").select { |pull| pull["merged_at"] }
            .map { |pull| [pull.fetch("number"), pull.fetch("title")] }
    end
    numbers.uniq.map do |number, title|
      files = github.get_all("repos/#{github.repo}/pulls/#{number}/files?per_page=100")
                    .flat_map { |file| [file.fetch("filename"), file["previous_filename"]].compact }
      Pull.new(number:, title:, reach: CIReach.suites(files))
    end
  end

  def open_issues(github)
    github.get_all("repos/#{github.repo}/issues?labels=#{LABEL}&state=open&per_page=100")
          .reject { |issue| issue.key?("pull_request") }
  end

  def ensure_label(github)
    return if github.get_all("repos/#{github.repo}/labels?per_page=100").any? { |label| label["name"] == LABEL }

    github.post("repos/#{github.repo}/labels",
                { name: LABEL, color: "d73a4a", description: "The scheduled suites run is red on main" })
  end

  def open_or_update(github, body)
    issue = open_issues(github).first
    payload = { title: body.title, body: body.to_s }
    if issue
      github.patch("repos/#{github.repo}/issues/#{issue.fetch('number')}", payload)
    else
      ensure_label(github)
      github.post("repos/#{github.repo}/issues", payload.merge(labels: [LABEL]))
    end
  end

  def close_issues(github, sha, run_url)
    open_issues(github).each do |issue|
      path = "repos/#{github.repo}/issues/#{issue.fetch('number')}"
      github.post("#{path}/comments", { body: "Green again at #{sha} ([run](#{run_url}))." })
      github.patch(path, { state: "closed", state_reason: "completed" })
    end
  end
end
