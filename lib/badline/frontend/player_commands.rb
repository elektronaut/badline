# frozen_string_literal: true

module Badline
  module Frontend
    # What the SID player's window does with an action a key or a click asks
    # for: one that picks or steps through the views or the SID models
    # changes the PlayerState, and any other goes on to the jukebox.
    class PlayerCommands
      VIEWS = PlayerHeader::VIEWS
      CHIPS = PlayerHeader::CHIPS

      def initialize(state)
        @state = state
      end

      # Returns the action for the jukebox, or nil when the window has
      # handled it.
      def handle(action)
        state = @state
        if action == :view then state.view = (state.view + 1) % VIEWS.size
        elsif action == :chip then state.chip = (state.chip + 1) % CHIPS.size
        elsif VIEWS.include?(action) then state.view = VIEWS.index(action)
        elsif CHIPS.include?(action) then state.chip = CHIPS.index(action)
        else return action
        end
        nil
      end
    end
  end
end
