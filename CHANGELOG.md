# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `config.apply()` no longer crashes when the legacy `command` config key is used
  (`cmd:trim()` → `vim.trim(cmd)`); this previously aborted `setup()` entirely.
- MCP server no longer errors when a client sends valid JSON that is not an
  object (scalar / `null`): the JSON-RPC error path no longer indexes a non-table.
- WebSocket frame parsing now distinguishes protocol violations from incomplete
  frames (`nil, -1` vs `nil, 0`); a malformed frame now closes the connection
  instead of wedging it forever and growing the read buffer unbounded.
- Fixed a double `uv_close` on keepalive timeout that threw inside a libuv
  callback ("handle is already closing").
- `close_client` now reports accurate state and guards against closing an
  already-closing handle.
- `openFile` line-range selection now uses a 1-based mark line and a valid
  column (was passing `col = -1` and an off-by-one line, so selection failed).
- Selection tracking `disable()` now also stops the pending demotion timer
  (was a uv handle leak that could fire against torn-down state).
- Terminal command splitting drops empty argv entries from repeated spaces.

## [0.2.0] - 2026-07-02

Adds a configurable keymap layer and the release/versioning infrastructure.
Backward compatible with 0.1.0 configurations.

### Added

- **Keymap module** (`cursoragent.keymaps`) with conventional, configurable
  defaults:
  - `<C-,>` toggles the Cursor Agent terminal in normal and terminal modes.
  - Per-variant normal mode keymaps via `keymaps.toggle.variants`
    (e.g. `{ ask = "<leader>caa" }`).
  - Buffer-local `<C-h/j/k/l>` window navigation and `<C-f/b>` scrolling inside
    Cursor Agent terminal buffers. These are buffer-local, so they never clash
    with your own global mappings.
  - Automatic which-key registration when which-key is installed.
- `:CursorAgentVersion` command and `cursoragent.version` module.
- `filetype=cursoragent_terminal` is now set on Cursor Agent terminal buffers so
  keymaps and integrations can identify them.
- Floating windows can now be closed with `<Esc>` as well as `q` (normal mode
  only, so `<Esc>` is still delivered to the interactive Cursor Agent TUI).

### Changed

- **Default keymaps are now enabled.** Users updating from `main` will get the
  `<C-,>` toggle mapping by default. Set any `keymaps.*` entry to `false` to
  disable it, for example `keymaps = { toggle = { normal = false } }`.

### Notes

- Fully backward compatible: existing configurations without a `keymaps` key
  continue to work unchanged; `config.validate` only checks `keymaps` when it is
  present.

## [0.1.0] - 2026-07-02

Baseline snapshot of the plugin as previously distributed on the `main` branch,
tagged so users can pin the pre-keymaps version with `tag = "v0.1.0"`.

### Added

- Terminal integration for the Cursor Agent CLI with native, snacks, and
  external terminal providers, plus agent/ask/plan/resume modes.
- MCP WebSocket server with selection tracking, `@` mention queueing, and IDE
  tools (diagnostics, open diff, open file, editors, workspace folders, etc.).
- Side-by-side diff visualization and automatic file refresh when the agent
  modifies open buffers.
- File explorer integrations (neo-tree, nvim-tree, oil.nvim) and git project
  root detection.

[Unreleased]: https://github.com/goodhee/cursoragent.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/goodhee/cursoragent.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/goodhee/cursoragent.nvim/releases/tag/v0.1.0
