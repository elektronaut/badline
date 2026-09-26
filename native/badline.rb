# frozen_string_literal: true

# The native badline: boots the machine (or attaches and autostarts the
# media given) and plays it in an SDL2 window. It builds with Spinel only;
# `rake native:build` builds it into tmp/native/badline. See
# native/README.md.
#
#   badline [media] [frames] [paced|unpaced] [sound] [screenshot.bmp]
#   badline --version

require "badline/native"

if ARGV.include?("--version")
  puts Badline::Native.version
  exit
end

media = ""
frames = 0
paced = true
screenshot = ""
sound = false
ARGV.each do |arg|
  if arg == "unpaced"
    paced = false
  elsif arg == "sound"
    sound = true
  elsif arg.end_with?(".bmp")
    screenshot = arg
  elsif arg.to_i.to_s == arg
    frames = arg.to_i
  elsif arg != "paced"
    media = arg
  end
end

computer = Badline::Computer.new
puts Badline::Media.attach(computer, media) unless media.empty?
Badline::Native::App.new(computer, frame_limit: frames, paced:, screenshot:, sound:).run
