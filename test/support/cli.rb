# frozen_string_literal: true

require "etc"

# Command-line helpers the headless runners share.
module CLI
  # Left well short of the core count: several workspaces share the
  # machine, and a suite that hogs it helps nobody.
  DEFAULT_SHARDS = 4

  module_function

  # Removes "--name value" or "--name=value" from argv, returning the value.
  def take_option(argv, name)
    index = argv.index { |arg| arg == name || arg.start_with?("#{name}=") }
    return unless index

    arg = argv.delete_at(index)
    arg.start_with?("#{name}=") ? arg.split("=", 2).last : argv.delete_at(index)
  end

  # --shards, else SHARDS in the environment, else the default, capped by
  # the cores actually available.
  def shard_count(requested)
    count = (requested || ENV.fetch("SHARDS", nil)).to_i
    count = DEFAULT_SHARDS unless count.positive?
    [count, Etc.nprocessors].min
  end
end
