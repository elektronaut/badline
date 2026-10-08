# frozen_string_literal: true

module Badline
  class Computer
    # The LOAD, SAVE and serial traps on the KERNAL a KernalTrap::Layout
    # describes, which serve the disk in device 8 (Attachments#mount).
    module KernalTraps
      private

      def install_kernal_traps(layout)
        @trap_layout = layout
        load_trap = KernalTrap::Load.new(cpu:, bus: address_bus, layout:, drive: @drive)
        cpu.install_trap(layout.load) { load_trap.call }
        @serial_trap = KernalTrap::Serial.new(cpu:, bus: address_bus, layout:, drive: @drive,
                                              device: serial_trap_device).install
        save_trap = @save_trap = KernalTrap::Save.new(cpu:, bus: address_bus, layout:, drive: @drive)
        cpu.install_trap(layout.save) { save_trap.call }
      end

      def remove_kernal_traps
        cpu.remove_trap(@trap_layout.load)
        cpu.remove_trap(@trap_layout.save)
        @serial_trap.uninstall
        @serial_trap = nil
        @save_trap = nil
      end
    end
  end
end
