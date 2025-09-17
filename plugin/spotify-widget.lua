-- plugin/spotify-player.lua
-- This file defines the user commands for the plugin.

-- Main command :Spotify that accepts arguments
vim.api.nvim_create_user_command("Spotify", function(args)
  require("spotify-player").handler(args)
end, {
    nargs = "?", -- Accepts 0 or 1 argument
    -- Autocompletion for the commands
    complete = function()
        return { "next", "previous", "volume_up", "volume_down", "toggle_shuffle", "toggle_repeat" }
    end,
    desc = "Control Spotify (play-pause, next, previous, etc.)"
})

-- Command to toggle the widget visibility
vim.api.nvim_create_user_command("SpotifyToggle", function()
  require("spotify-player").toggle()
end, {
  desc = "Show/Hide the Spotify status window",
})
