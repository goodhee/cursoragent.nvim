---@mod cursoragent.keymaps Keymap management for cursoragent.nvim
---@brief [[
--- This module provides keymap registration and handling for cursoragent.nvim.
--- It handles normal mode, terminal mode, variant, window navigation, and
--- scrolling keymaps. All keymaps are opt-out: set the relevant config entry to
--- false to disable it.
---@brief ]]

local M = {}

---Register global keymaps for cursoragent.nvim
---@param cursor_agent table The main plugin module
---@param config table The plugin configuration
function M.register_keymaps(cursor_agent, config)
  local keymaps = config and config.keymaps
  if not keymaps then
    return
  end

  local map_opts = { noremap = true, silent = true }
  local toggle = keymaps.toggle or {}

  -- Normal mode toggle keymap
  if toggle.normal then
    vim.api.nvim_set_keymap(
      "n",
      toggle.normal,
      [[<cmd>CursorAgent<CR>]],
      vim.tbl_extend("force", map_opts, { desc = "Cursor Agent: Toggle" })
    )
  end

  -- Terminal mode toggle keymap (escape terminal mode first for reliability)
  if toggle.terminal then
    vim.api.nvim_set_keymap(
      "t",
      toggle.terminal,
      [[<C-\><C-n>:CursorAgent<CR>]],
      vim.tbl_extend("force", map_opts, { desc = "Cursor Agent: Toggle" })
    )
  end

  -- Variant keymaps (map to auto-generated CursorAgent<Variant> commands)
  if toggle.variants then
    for variant_name, keymap in pairs(toggle.variants) do
      if keymap then
        local capitalized_name = variant_name:gsub("^%l", string.upper)
        local cmd_name = "CursorAgent" .. capitalized_name
        vim.api.nvim_set_keymap(
          "n",
          keymap,
          string.format([[<cmd>%s<CR>]], cmd_name),
          vim.tbl_extend("force", map_opts, { desc = "Cursor Agent: " .. capitalized_name })
        )
      end
    end
  end

  -- Register with which-key if available (best-effort, never fatal)
  vim.defer_fn(function()
    local ok, which_key = pcall(require, "which-key")
    if not ok then
      return
    end
    if toggle.normal then
      which_key.add({ mode = "n", { toggle.normal, desc = "Cursor Agent: Toggle", icon = "🤖" } })
    end
    if toggle.terminal then
      which_key.add({ mode = "t", { toggle.terminal, desc = "Cursor Agent: Toggle", icon = "🤖" } })
    end
    if toggle.variants then
      for variant_name, keymap in pairs(toggle.variants) do
        if keymap then
          local capitalized_name = variant_name:gsub("^%l", string.upper)
          which_key.add({ mode = "n", { keymap, desc = "Cursor Agent: " .. capitalized_name, icon = "🤖" } })
        end
      end
    end
  end, 100)

  -- Attach terminal-local navigation/scrolling keymaps whenever a cursoragent
  -- terminal buffer is created (identified by its filetype).
  M.setup_terminal_navigation(cursor_agent, config)
end

---Set up buffer-local terminal navigation and scrolling keymaps via a FileType
---autocmd so they apply to every cursoragent terminal buffer.
---@param cursor_agent table The main plugin module
---@param config table The plugin configuration
function M.setup_terminal_navigation(cursor_agent, config)
  local keymaps = config and config.keymaps
  if not keymaps then
    return
  end
  if not (keymaps.window_navigation or keymaps.scrolling) then
    return
  end

  local augroup = vim.api.nvim_create_augroup("CursorAgentTerminalKeymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "cursoragent_terminal",
    callback = function(args)
      local buf = args.buf
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      local buf_opts = { noremap = true, silent = true }

      if keymaps.window_navigation then
        local directions = { h = "left", j = "down", k = "up", l = "right" }
        for key, dir in pairs(directions) do
          vim.api.nvim_buf_set_keymap(
            buf,
            "t",
            "<C-" .. key .. ">",
            string.format(
              [[<C-\><C-n><C-w>%s:lua require("cursoragent").force_insert_mode()<CR>]],
              key
            ),
            vim.tbl_extend("force", buf_opts, { desc = "Window: move " .. dir })
          )
          vim.api.nvim_buf_set_keymap(
            buf,
            "n",
            "<C-" .. key .. ">",
            string.format([[<C-w>%s:lua require("cursoragent").force_insert_mode()<CR>]], key),
            vim.tbl_extend("force", buf_opts, { desc = "Window: move " .. dir })
          )
        end
      end

      if keymaps.scrolling then
        vim.api.nvim_buf_set_keymap(
          buf,
          "t",
          "<C-f>",
          [[<C-\><C-n><C-f>i]],
          vim.tbl_extend("force", buf_opts, { desc = "Scroll full page down" })
        )
        vim.api.nvim_buf_set_keymap(
          buf,
          "t",
          "<C-b>",
          [[<C-\><C-n><C-b>i]],
          vim.tbl_extend("force", buf_opts, { desc = "Scroll full page up" })
        )
      end
    end,
    desc = "Attach cursoragent terminal navigation keymaps",
  })
end

return M
