-- lua/spotify-player/init.lua
-- Lógica principal y comandos para el plugin spotify-player.nvim.
-- Este archivo está corregido para funcionar sin necesidad de llamar a setup().

local M = {}

-- -----------------------------------------------------------------------------
-- Helpers para la configuración
-- -----------------------------------------------------------------------------

-- Función para crear una copia profunda de una tabla, para evitar modificar la configuración por defecto.
local function deepcopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            v = deepcopy(v)
        end
        copy[k] = v
    end
    return copy
end

-- Fusiona la tabla 'b' en la 'a', modificando 'a'.
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

-- -----------------------------------------------------------------------------
-- Configuración por Defecto
-- -----------------------------------------------------------------------------
local defaults = {
  -- Ajustes generales
  player = "spotify", -- Nombre para playerctl (ej. "spotify", "spotifyd")
  interval_ms = 1000, -- Intervalo de actualización en milisegundos

  -- Apariencia de la ventana
  width = 45,        -- Ancho en columnas
  height = 7,        -- Alto en líneas
  row_offset = 3,    -- Distancia desde el borde inferior de Neovim
  col_offset = 2,    -- Distancia desde el borde derecho de Neovim
  border = "rounded",-- Estilo del borde (ver :help nvim_open_win)

  -- Iconos (requiere una Nerd Font)
  icons = {
    track = "🎵", artist = "👥", album = "💿",
    shuffle_on = "🔀", shuffle_off = "→",
    repeat_on = "🔁", repeat_off = "→",
    volume = "🔊", playing = "▶", paused = "⏸", stopped = "⏹",
    progress_indicator = "●", progress_filled = "─", progress_empty = "·",
  },

  -- Atajos de teclado (configura `enabled = true` en tu setup para activarlos)
  keymaps = {
    enabled = false,
    volume_up = "<leader>s+", volume_down = "<leader>s-",
    previous = "<leader>sP", next = "<leader>sn",
    play_pause = "<leader>sp", toggle_repeat = "<leader>sr",
    toggle_shuffle = "<leader>ss", toggle_widget = "<leader>st",
  },

  -- Mostrar notificaciones para las acciones (ej. "Siguiente canción")
  show_notifications = true,
}

-- La configuración se inicializa con los valores por defecto.
-- Esto hace que el plugin funcione sin necesidad de llamar a M.setup().
local cfg = deepcopy(defaults)

-- -----------------------------------------------------------------------------
-- Estado Interno
-- -----------------------------------------------------------------------------
M._buf = nil
M._win = nil
M._timer = nil

-- -----------------------------------------------------------------------------
-- Funciones Auxiliares
-- -----------------------------------------------------------------------------

-- Ejecuta un comando de sistema y devuelve la primera línea del resultado.
local function safe_system(cmd)
  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 or not output or vim.tbl_isempty(output) then
    return nil
  end
  return output[1]
end

-- Comprueba si playerctl está disponible en el sistema.
local function playerctl_available()
  return vim.fn.executable("playerctl") == 1
end

-- Formatea un string de segundos al formato MM:SS.
local function format_time(seconds_str)
  local sec = tonumber(seconds_str)
  if not sec or sec < 0 then return "00:00" end
  local mins = math.floor(sec / 60)
  local secs = math.floor(sec % 60)
  return string.format("%02d:%02d", mins, secs)
end

-- Centra un texto en un ancho dado, considerando caracteres anchos (iconos).
local function center_text(text, width)
    local text_len = vim.fn.strwidth(text)
    if text_len >= width then return text end
    local padding = math.floor((width - text_len) / 2)
    return string.rep(" ", padding) .. text .. string.rep(" ", width - text_len - padding)
end

-- -----------------------------------------------------------------------------
-- Lógica Principal
-- -----------------------------------------------------------------------------

-- Obtiene toda la información necesaria del reproductor.
local function get_player_info()
  if not playerctl_available() then
    return nil, "Error: `playerctl` no está instalado."
  end

  local player = cfg.player
  local status_cmd = string.format("playerctl -p %s status 2>/dev/null", player)
  local status = safe_system(status_cmd)

  if not status then
    return nil, string.format("Reproductor '%s' no activo.", player)
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

-- Formatea la información del reproductor en líneas para la ventana.
local function format_content(info)
  if not info then return { "Reproductor desconectado" } end

  local lines = {}
  local bar_width = cfg.width - 4 -- Ancho para la barra de progreso

  local status_icon = cfg.icons.stopped
  if info.status:lower():find("play") then status_icon = cfg.icons.playing end
  if info.status:lower():find("pause") then status_icon = cfg.icons.paused end

  local shuffle_icon = (info.shuffle == "On") and cfg.icons.shuffle_on or cfg.icons.shuffle_off
  local repeat_icon = (info.loop ~= "None") and cfg.icons.repeat_on or cfg.icons.repeat_off

  lines[1] = string.format(" %s  %s", cfg.icons.track, info.title or "Desconocido")
  lines[2] = string.format(" %s  %s", cfg.icons.artist, info.artist or "Desconocido")
  lines[3] = string.format(" %s  %s", cfg.icons.album, info.album or "Desconocido")
  lines[4] = "" -- Línea en blanco

  local volume_pct = math.floor((tonumber(info.volume) or 0) * 100)
  local controls_line = string.format("%s   %s   %s   %s %d%%", shuffle_icon, repeat_icon, status_icon, cfg.icons.volume, volume_pct)
  lines[5] = center_text(controls_line, bar_width + 2)

  local pos_s = tonumber(info.position) or 0
  local len_s = (tonumber(info.length) or 0) / 1000000 -- mpris:length está en microsegundos
  local time_str = string.format("%s / %s", format_time(pos_s), format_time(len_s))
  
  local progress_pct = 0
  if len_s > 0 then progress_pct = (pos_s / len_s) end

  local indicator_pos = math.floor(bar_width * progress_pct)
  local progress_bar = ""
  for i = 1, bar_width do
    if i == indicator_pos then progress_bar = progress_bar .. cfg.icons.progress_indicator
    elseif i < indicator_pos then progress_bar = progress_bar .. cfg.icons.progress_filled
    else progress_bar = progress_bar .. cfg.icons.progress_empty end
  end
  lines[6] = " " .. progress_bar .. " "
  lines[7] = center_text(time_str, bar_width + 2)

  return lines
end

-- Actualiza el contenido de la ventana una vez.
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
-- Gestión de Ventana y Temporizador
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

local function stop_timer()
  if M._timer then
    pcall(function() M._timer:stop() end)
    pcall(function() M._timer:close() end)
    M._timer = nil
  end
end

local function start_timer()
  if M._timer and not M._timer:is_closing() then return end
  M._timer = vim.loop.new_timer()
  M._timer:start(0, cfg.interval_ms, vim.schedule_wrap(update_once))
end

-- -----------------------------------------------------------------------------
-- API Pública y Comandos
-- -----------------------------------------------------------------------------

-- Función para mostrar/ocultar la ventana flotante.
function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    stop_timer()
    close_window()
  else
    open_window()
    start_timer()
  end
end

-- Función genérica para enviar comandos a playerctl.
local function run_command(action, notification_msg)
  if not playerctl_available() then
    vim.notify("spotify-player: `playerctl` no está instalado.", vim.log.levels.ERROR)
    return
  end
  vim.fn.system(string.format("playerctl -p %s %s", cfg.player, action))
  if cfg.show_notifications and notification_msg then
      vim.notify("Spotify: " .. notification_msg, vim.log.levels.INFO, { title = "Control Spotify" })
  end
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.schedule(update_once)
  end
end

-- Manejador para el comando :Spotify.
function M.handler(args)
    local action = args.fargs[1]
    if not action or action == "" then
        run_command("play-pause", "Cambiado Play/Pause")
    elseif action == "next" then
        run_command("next", "Siguiente Canción")
    elseif action == "previous" then
        run_command("previous", "Canción Anterior")
    elseif action == "volume_up" then
        run_command("volume 0.05+", "Volumen +")
    elseif action == "volume_down" then
        run_command("volume 0.05-", "Volumen -")
    elseif action == "toggle_shuffle" then
        run_command("shuffle Toggle", "Cambiado Aleatorio")
    elseif action == "toggle_repeat" then
        local current_loop = safe_system(string.format("playerctl -p %s loop", cfg.player))
        if current_loop == "None" then run_command("loop Playlist", "Repetir: Playlist")
        elseif current_loop == "Playlist" then run_command("loop Track", "Repetir: Canción")
        else run_command("loop None", "Repetir: No") end
    else
        vim.notify("spotify-player: Comando desconocido '" .. action .. "'", vim.log.levels.WARN)
    end
end

-- Configura los atajos de teclado definidos en la configuración.
local function setup_keymaps()
  if not cfg.keymaps.enabled then return end
  local map = vim.keymap.set
  local opts = { noremap = true, silent = true, desc = "Control Spotify" }
  map("n", cfg.keymaps.toggle_widget, M.toggle, { noremap = true, silent = true, desc = "Alternar Spotify Player" })
  map("n", cfg.keymaps.play_pause, function() M.handler({ fargs = { "" } }) end, opts)
  map("n", cfg.keymaps.next, function() M.handler({ fargs = { "next" } }) end, opts)
  map("n", cfg.keymaps.previous, function() M.handler({ fargs = { "previous" } }) end, opts)
  map("n", cfg.keymaps.volume_up, function() M.handler({ fargs = { "volume_up" } }) end, opts)
  map("n", cfg.keymaps.volume_down, function() M.handler({ fargs = { "volume_down" } }) end, opts)
  map("n", cfg.keymaps.toggle_shuffle, function() M.handler({ fargs = { "toggle_shuffle" } }) end, opts)
  map("n", cfg.keymaps.toggle_repeat, function() M.handler({ fargs = { "toggle_repeat" } }) end, opts)
end

-- Función de setup principal (opcional).
function M.setup(opts)
  -- Fusiona las opciones del usuario con la configuración actual.
  deep_merge(cfg, opts or {})
  setup_keymaps()
end

-- -----------------------------------------------------------------------------
-- Creación de Comandos de Neovim
-- -----------------------------------------------------------------------------
-- Se crean aquí para que el plugin funcione sin necesidad de un archivo `plugin/`.

-- Comando :Spotify que acepta argumentos
vim.api.nvim_create_user_command("Spotify", function(args)
  M.handler(args)
end, {
    nargs = "?", -- Acepta 0 o 1 argumento
    complete = function()
        return { "next", "previous", "volume_up", "volume_down", "toggle_shuffle", "toggle_repeat" }
    end,
    desc = "Controla Spotify (play-pause, next, previous, etc.)"
})

-- Comando para mostrar/ocultar el widget
vim.api.nvim_create_user_command("SpotifyToggle", function()
  M.toggle()
end, {
  desc = "Muestra/Oculta la ventana de estado de Spotify",
})

-- Limpieza al salir de Neovim
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    stop_timer()
    close_window()
  end,
})

return M
