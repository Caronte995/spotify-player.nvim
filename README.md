# 🎵 spotify-player.nvim

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**spotify-player.nvim** is a lightweight and elegant plugin for **Neovim** that displays the current playback status of Spotify (or another player compatible with `playerctl`) and allows you to control it without leaving the editor.

---

## Table of Contents

- [Features](#features)
- [Screenshot / Image](#screenshot--image)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Commands](#commands)
  - [Available Actions](#available-actions)
  - [Shortcuts / Keymaps](#shortcuts--keymaps)
- [Configuration](#configuration)
- [Contribute](#contribute)
- [Acknowledgments](#acknowledgments)
- [License](#license)

---

## Features

- Floating window displaying the current song, artist, and album.
- Built-in controls: `Play/Pause`, `Next/Previous`, `Volume`, `Shuffle`, and `Repeat`.
- Visual progress bar and playback time.
- Highly configurable.
- Very lightweight — only one external dependency: `playerctl`.

---

## Screenshot / Image

```markdown
<img width="707" height="281" alt="Image" src="https://github.com/user-attachments/assets/1b0e7fea-a6e5-48fb-8ccf-1b6264f8a665" />

<img width="1920" height="1080" alt="Image" src="https://github.com/user-attachments/assets/8f500843-0b28-45f8-806b-c72cbd652e4b" >
```

---

## Requirements

- **Neovim** `v0.7+`
- **playerctl** — command line utility to control media players (Spotify, mpv, etc.)
  - Debian/Ubuntu: `sudo apt install playerctl`
  - Arch Linux: `sudo pacman -S playerctl`
  - macOS (Homebrew): `brew install playerctl`
- A **Nerd Font** installed and configured in your terminal to display icons correctly (optional, but recommended).

---

## Installation

Install the plugin with your favorite plugin manager. Example with `lazy.nvim` (make sure to use straight quotes):

```lua
-- lua/plugins/spotify.lua
return {
  {
    “Caronte995/spotify-player.nvim”,
    opts = {
      -- You can add your custom options here if you want
    },
    -- optional lazy-loading:
    cmd = { “SpotifyToggle”, “Spotify” },
  }
}
```

---

## Usage

### Commands

- `:SpotifyToggle` — Show or hide the player window.
- `:Spotify [action]` — Control the player. If `action` is not specified, toggle `play/pause`.

### Available actions

- `next`
- `previous`
- `volume_up`
- `volume_down`
- `toggle_shuffle`
- `toggle_repeat`
- `play` / `pause` / `stop` (according to `playerctl`)

Example from the Neovim command line:

```vim
:Spotify next
:Spotify volume_up
```

### Shortcuts / Keymaps

There are two ways to enable shortcuts:

**1. Automatic mode (easy)** — activate from the options (see configuration below):

```lua
require(“spotify-player”).setup({
  keymaps = {
    enabled = true,
  }
})
```

**2. Manual mode** — define your own shortcuts (example in `lua/keymaps.lua`):

```lua
local spotify = require(“spotify-player”)

-- Normal mode
vim.keymap.set(“n”, “<leader>st”, spotify.toggle, { desc = “Toggle Spotify Player” })
vim.keymap.set(“n”, “<leader>sn”, function() vim.cmd(“Spotify next”) end, { desc = “Spotify Next” })
vim.keymap.set(“n”, “<leader>sp”, function() vim.cmd(“Spotify previous”) end, { desc = “Spotify Previous” })
vim.keymap.set(“n”, “<leader>sv+”, function() vim.cmd(“Spotify volume_up”) end, { desc = “Spotify Vol +” })
vim.keymap.set(“n”, “<leader>sv-”, function() vim.cmd(“Spotify volume_down”) end, { desc = “Spotify Vol -” })
```

> Adjust the keys `<leader>st`, etc., to your liking.

---

## Configuration

The plugin is configured by calling `setup()` and passing a table with options. Basic example and suggested default options:

```lua
-- lua/plugins/spotify.lua or in your init.lua
require(“spotify-player”).setup({
  playerctl_cmd = “playerctl”,       -- Path/executable of playerctl
  update_interval = 1000,            -- milliseconds between status updates
  float = {
    width = 60,
    height = 8,
    border = “rounded”,              -- ‘none’ | ‘single’ | ‘double’ | ‘rounded’ | ...
    winblend = 10,
  },
  show_progress = true,              -- show progress bar
  icons = {
    play = “”,                      -- Nerd Fonts recommended
    pause = “”,
    next = “⏭”,
    prev = “⏮”,
    vol_up = “”,
    vol_down = “”,
    shuffle = “🔀”,
    repeat = “🔁”,
  },
  keymaps = {
    enabled = false,                 -- true to enable default shortcuts
    toggle = “<leader>st”,
    next = “<leader>sn”,
    previous = “<leader>sp”,
    vol_up = “<leader>sv+”,
    vol_down = “<leader>sv-”,
  },
})
```

If the plugin provides more options, add them to the `setup({ ... })` table.

---

## Contribute

Contributions are welcome! If you want to collaborate:

1. Fork the repository.
2. Create a new branch: `git checkout -b feat/my-change`.
3. Make your changes and add tests/examples if applicable.
4. Open a Pull Request clearly describing the changes.

Suggestions welcome: UI improvements (progress bar, layout), support for more players, accessibility options, and more configurable shortcuts.

---

## Acknowledgments

This project is inspired by ideas from `stsewd/spotify.nvim`. Many thanks to the author for the inspiration and ideas.

---

## License

**MIT** license — see `LICENSE` in the repository.
