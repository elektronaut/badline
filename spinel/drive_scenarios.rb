# frozen_string_literal: true

# Runs true-drive scenarios with the same DriveScenarios.run that
# bin/drive_scenarios runs them with, and prints a baseline row per check.
# Takes a scratch directory for the disk images and the scenarios to run.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/drive_scenarios.rb DIR save format
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/drive_scenarios.rb -o tmp/spinel/drive_scenarios
#   tmp/spinel/drive_scenarios DIR save format

require "badline/core"
require_relative "../test/drive_scenarios"

raise "Usage: drive_scenarios DIR SCENARIO..." if ARGV.length < 2

dir = ARGV[0]
ARGV.drop(1).each do |name|
  print DriveScenarios.run(name, dir)
  $stdout.flush
end
