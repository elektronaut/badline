# frozen_string_literal: true

# The emulator core: the machine, its chips, media and traps, and the
# snapshot state C64 saves and restores with, without the options,
# the rest of the snapshot code, audio or front end. lib/badline.rb and
# the Spinel harnesses in spinel/ load it, so a file the core needs is
# added here.
require "badline/version"
require "badline/integer_helper"
require "badline/region"
require "badline/timing"
require "badline/model"
require "badline/addressable"
require "badline/memory"
require "badline/c64/color_memory"
require "badline/rom"
require "badline/c64/banked_ram"
require "badline/status"
require "badline/input"
require "badline/chips"
require "badline/drives"
require "badline/c64/bus"
require "badline/c64/reu"
require "badline/snapshot/state"
require "badline/snapshot/c64_setup"
require "badline/snapshot/storage_setup"
require "badline/machine"
require "badline/c64"
require "badline/vic20"
require "badline/storage"
require "badline/sid_tune"
require "badline/c64/cartridge"
require "badline/kernal_trap"
require "badline/media"
