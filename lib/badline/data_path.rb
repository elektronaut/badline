# frozen_string_literal: true

require "fileutils"

module Badline
  class << self
    attr_writer :data_path

    # The per-user folder badline keeps its own files in. Defaults to
    # $BADLINE_DATA_PATH, then to the platform's folder for application
    # data. Assigning nil restores the default. Nothing is created until
    # data_folder is asked for a subfolder.
    def data_path
      @data_path ||= ENV.fetch("BADLINE_DATA_PATH", nil) || default_data_path(RUBY_PLATFORM)
    end

    # ~/Library/Application Support/badline on macOS, and
    # $XDG_DATA_HOME/badline or ~/.local/share/badline elsewhere.
    def default_data_path(platform)
      return File.join(Dir.home, "Library", "Application Support", "badline") if platform.include?("darwin")

      xdg = ENV.fetch("XDG_DATA_HOME", nil)
      xdg = File.join(Dir.home, ".local", "share") if xdg.nil? || !xdg.start_with?("/")
      File.join(xdg, "badline")
    end

    # The quicksaves, autosaves or saves subfolder of data_path, created
    # along with data_path if it doesn't exist yet.
    def data_folder(name)
      raise ArgumentError, "unknown data folder: #{name}" unless %w[quicksaves autosaves saves].include?(name)

      path = File.join(data_path, name)
      FileUtils.mkdir_p(path)
      path
    end
  end
end
