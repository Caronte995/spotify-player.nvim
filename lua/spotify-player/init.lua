-- lua/spotify-player/init.lua
-- Core logic for the spotify-player.nvim plugin.

local M = {}

-- -----------------------------------------------------------------------------
-- Default Configuration
-- -----------------------------------------------------------------------------
local defaults = {
  -- General settings
  player = "spotify", -- Player name for playerctl (e.g., "spotify", "spotifyd")
  interval_ms = 1000, -- Update interval in milliseconds

  -- Window appearance
  width = 45,        -- Window width in columns
  height = 7,        -- Window height in lines
  row_offset = 3,    -- Offset from the bottom edge of Neovim
  col_offset = 2,    -- Offset from the right edge of Neovim
  border = "rounded",-- Border style (see :help nvim_open_win)

  -- Icons (requires a Nerd Font)
  icons = {
    track = "🎵",
    artist = "👥",
    album = "💿",
    shuffle_on = "🔀",
    shuffle_off = "→",
    repeat_on = "🔁",
    repeat_off = "→",
    volume = "🔊",
    playing = "▶",
    paused = "⏸",
    stopped = "⏹",
    progress_indicator = "●",
    progress_filled = "─",
    progress_empty = "·",
  },

  -- Keymaps (set `enabled = true` to activate)
  keymaps = {
    enabled = false, -- Set to true to automatically set keymaps
    volume_up = "<leader>s+",
    volume_down = "<leader>s-",
    previous = "<leader>sP",
    next = "<leader>sn",
    play_pause = "<leader>sp",
    toggle_repeat = "<leader>sr",
    toggle_shuffle = "<leader>ss",
    toggle_widget = "<leader>st",
  },

  -- Show notifications for actions (e.g., "Next track")
  show_notifications = true,
}

-- User configuration will be stored here after setup() is called.
local cfg = {}

-- -----------------------------------------------------------------------------
-- Internal State
-- -----------------------------------------------------------------------------
M._buf = nil
M._win = nil
M._timer = nil

-- -----------------------------------------------------------------------------
-- Helper Functions
-- -----------------------------------------------------------------------------

-- Deep merge two tables. `b` overwrites `a`.
local function deep_merge(a, b)
  for k, v in pairs(b) do
    if type(v) == "table" and type(a[k]) == "table" then
      deep_merge(a[k], v)
    else
      a[k] = v
    end
  end
  return a
end

-- Safely execute a system command and return the first line of output.
local function safe_system(cmd)
  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 or not output or vim.tbl_isempty(output) then
    return nil
  end
  return output[1]
end

-- Check if playerctl is available on the system.
local function playerctl_available()
  return vim.fn.executable("playerctl") == 1
end

-- Format a string of seconds into MM:SS format.
local function format_time(seconds_str)
  local sec = tonumber(seconds_str)
  if not sec or sec < 0 then return "00:00" end
  local mins = math.floor(sec / 60)
  local secs = math.floor(sec % 60)
  return string.format("%02d:%02d", mins, secs)
end

-- Center text within a given width, accounting for wide characters (icons).
local function center_text(text, width)
    local text_len = vim.fn.strwidth(text)
    if text_len >= width then return text end
    local padding = math.floor((width - text_len) / 2)
    return string.rep(" ", padding) .. text .. string.rep(" ", width - text_len - padding)
end

-- -----------------------------------------------------------------------------
-- Main Logic
-- -----------------------------------------------------------------------------

-- Get all necessary information from the music player.
local function get_player_info()
  if not playerctl_available() then
    return nil, "Error: `playerctl` is not installed."
  end

  local player = cfg.player
  local status_cmd = string.format("playerctl -p %s status 2>/dev/null", player)
  local status = safe_system(status_cmd)

  if not status then
    return nil, string.format("Player '%s' is not active.", player)
  end

  return {
    status = status,
    title = safe_system(string.format("playerctl -p %s metadata --format '{{title}}'", player)),
    artist = safe_system(string.format("playerctl -p %s metadata --format '{{artist}}'", player)),
    album = safe_system(string.format("playerctl -p %s metadata --format '{{album}}'", player)),
    position = safe_system(string.format("playerctl -p %s position", player)),
    length = safe_system(string.format("playerctl -p %s metadata --format '{{mpris:length}}'", player)),
    shuffle = safe_system(string.format("playerctl -p %s shuffle", player)),
    loop = safe_system(string.format("playerctl -p %s loop", player)),
    volume = safe_system(string.format("playerctl -p %s volume", player)),
  }
end

-- Format the retrieved player information into lines for the window.
local function format_content(info)
  if not info then return { "Player disconnected" } end

  local lines = {}
  local bar_width = cfg.width - 4 -- Width for the progress bar

  -- Status Icons
  local status_icon = cfg.icons.stopped
  if info.status:lower():find("play") then status_icon = cfg.icons.playing end
  if info.status:lower():find("pause") then status_icon = cfg.icons.paused end

  local shuffle_icon = (info.shuffle == "On") and cfg.icons.shuffle_on or cfg.icons.shuffle_off
  local repeat_icon = (info.loop ~= "None") and cfg.icons.repeat_on or cfg.icons.repeat_off

  -- Song Info
  lines[1] = string.format(" %s  %s", cfg.icons.track, info.title or "Unknown")
  lines[2] = string.format(" %s  %s", cfg.icons.artist, info.artist or "Unknown")
  lines[3] = string.format(" %s  %s", cfg.icons.album, info.album or "Unknown")
  lines[4] = "" -- Blank line

  -- Controls
  local volume_pct = math.floor((tonumber(info.volume) or 0) * 100)
  local controls_line = string.format("%s   %s   %s   %s %d%%", shuffle_icon, repeat_icon, status_icon, cfg.icons.volume, volume_pct)
  lines[5] = center_text(controls_line, bar_width + 2)

  -- Progress Bar and Time
  local pos_s = tonumber(info.position) or 0
  local len_s = (tonumber(info.length) or 0) / 1000000 -- mpris:length is in microseconds
  local time_str = string.format("%s / %s", format_time(pos_s), format_time(len_s))
  
  local progress_pct = 0
  if len_s > 0 then progress_pct = (pos_s / len_s) end

  local indicator_pos = math.floor(bar_width * progress_pct)
  local progress_bar = ""
  for i = 1, bar_width do
    if i == indicator_pos then
      progress_bar = progress_bar .. cfg.icons.progress_indicator
    elseif i < indicator_pos then
      progress_bar = progress_bar .. cfg.icons.progress_filled
    else
      progress_bar = progress_bar .. cfg.icons.progress_empty
    end
  end
  lines[6] = " " .. progress_bar .. " "
  lines[7] = center_text(time_str, bar_width + 2)

  return lines
end

-- Update the window content once.
local function update_once()
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end

  local info, err = get_player_info()
  local lines
  if not info then
    lines = { center_text(err, cfg.width - 2) }
  else
    lines = format_content(info)
  end

  vim.api.nvim_buf_set_option(M._buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M._buf, "modifiable", false)
end


-- -----------------------------------------------------------------------------
-- Window & Timer Management
-- -----------------------------------------------------------------------------

local function make_buffer()
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then return end
  M._buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M._buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M._buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(M._buf, "swapfile", false)
end

local function open_window()
  if M._win and vim.api.nvim_win_is_valid(M._win) then return end

  make_buffer()

  local width = math.min(cfg.width, vim.o.columns - 2)
  local height = math.min(cfg.height, vim.o.lines - 2)
  local row = vim.o.lines - height - cfg.row_offset
  local col = vim.o.columns - width - cfg.col_offset

  local opts = {
    style = "minimal", relative = "editor", width = width,
    height = height, row = row, col = col,
    border = cfg.border, noautocmd = true,
  }

  M._win = vim.api.nvim_open_win(M._buf, false, opts)

  vim.api.nvim_win_set_option(M._win, "winblend", 0)
  vim.api.nvim_win_set_option(M._win, "cursorline", false)
  vim.api.nvim_win_set_option(M._win, "wrap", false)

  -- Keymaps to close the window
  local keymap_opts = { buffer = M._buf, silent = true }
  vim.keymap.set("n", "q", M.toggle, keymap_opts)
  vim.keymap.set("n", "<Esc>", M.toggle, keymap_opts)
end

local function close_window()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
    M._win = nil
  end
end

local function start_timer()
  if M._timer and not M._timer:is_closing() then return end
  M._timer = vim.loop.new_timer()
  M._timer:start(0, cfg.interval_ms, vim.schedule_wrap(update_once))
end

local function stop_timer()
  if M._timer then
    pcall(function() M._timer:stop() end)
    pcall(function() M._timer:close() end)
    M._timer = nil
  end
end

-- -----------------------------------------------------------------------------
-- Public API & Commands
-- -----------------------------------------------------------------------------

-- Function to toggle the floating window.
function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    stop_timer()
    close_window()
  else
    open_window()
    start_timer()
  end
end

-- Generic function to send commands to playerctl.
local function run_command(action, notification_msg)
  if not playerctl_available() then
    vim.notify("spotify-player: `playerctl` not installed.", vim.log.levels.ERROR)
    return
  end
  vim.fn.system(string.format("playerctl -p %s %s", cfg.player, action))
  if cfg.show_notifications and notification_msg then
      vim.notify("Spotify: " .. notification_msg, vim.log.levels.INFO, { title = "Spotify Control" })
  end
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.schedule(update_once)
  end
end

-- Main handler for the :Spotify command.
function M.handler(args)
    local action = args.fargs[1]
    if not action or action == "" then
        run_command("play-pause", "Toggled Play/Pause")
    elseif action == "next" then
        run_command("next", "Next Track")
    elseif action == "previous" then
        run_command("previous", "Previous Track")
    elseif action == "volume_up" then
        run_command("volume 0.05+", "Volume Up")
    elseif action == "volume_down" then
        run_command("volume 0.05-", "Volume Down")
    elseif action == "toggle_shuffle" then
        run_command("shuffle Toggle", "Toggled Shuffle")
    elseif action == "toggle_repeat" then
        local current_loop = safe_system(string.format("playerctl -p %s loop", cfg.player))
        if current_loop == "None" then
            run_command("loop Playlist", "Repeat: Playlist")
        elseif current_loop == "Playlist" then
            run_command("loop Track", "Repeat: Track")
        else
            run_command("loop None", "Repeat: Off")
        end
    else
        vim.notify("spotify-player: Unknown command '" .. action .. "'", vim.log.levels.WARN)
    end
end

-- Sets up the keymaps defined in the config.
local function setup_keymaps()
  if not cfg.keymaps.enabled then return end
  local map = vim.keymap.set
  local opts = { noremap = true, silent = true, desc = "Spotify Control" }

  map("n", cfg.keymaps.toggle_widget, M.toggle, { noremap = true, silent = true, desc = "Toggle Spotify Player" })
  map("n", cfg.keymaps.play_pause, function() M.handler({ fargs = { "" } }) end, opts)
  map("n", cfg.keymaps.next, function() M.handler({ fargs = { "next" } }) end, opts)
  map("n", cfg.keymaps.previous, function() M.handler({ fargs = { "previous" } }) end, opts)
  map("n", cfg.keymaps.volume_up, function() M.handler({ fargs = { "volume_up" } }) end, opts)
  map("n", cfg.keymaps.volume_down, function() M.handler({ fargs = { "volume_down" } }) end, opts)
  map("n", cfg.keymaps.toggle_shuffle, function() M.handler({ fargs = { "toggle_shuffle" } }) end, opts)
  map("n", cfg.keymaps.toggle_repeat, function() M.handler({ fargs = { "toggle_repeat" } }) end, opts)
end

-- The main setup function for the plugin.
function M.setup(opts)
  cfg = deep_merge(defaults, opts or {})
  setup_keymaps()

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      stop_timer()
      close_window()
    end,
  })
end

return M
