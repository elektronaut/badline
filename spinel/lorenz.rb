# frozen_string_literal: true

# Runs the Wolfgang Lorenz chain the way bin/lorenz does, with the same
# Lorenz::Chain, and prints what the run recorded for CRuby to turn into
# baseline rows (Lorenz::Run.parse): a "load OFFSET NAME" line for each
# program the suite loaded, a "key OFFSET" line for each key injected,
# "result RESULT CYCLES", then "transcript LENGTH" and the transcript.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/lorenz.rb image [--resume NAME] [--stop-after NAME]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/lorenz.rb -o tmp/spinel/lorenz
#   tmp/spinel/lorenz image [--resume NAME] [--stop-after NAME]

require_relative "lorenz_kernel"

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
raise "Usage: lorenz image [--resume NAME] [--stop-after NAME]" if image.empty?

print Lorenz.run_chain(image, resume, stop_after, 10_000_000_000)
