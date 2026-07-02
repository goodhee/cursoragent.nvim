---@mod cursoragent.commands Command registration for cursoragent.nvim
---@brief [[
--- This module provides command registration and handling for cursoragent.nvim.
--- It defines user commands and command handlers.
---@brief ]]

local M = {}

---Register commands for the cursoragent plugin
---@param cursor_agent table The main plugin module
function M.register_commands(cursor_agent)
  vim.api.nvim_create_user_command('CursorAgent', function()
    cursor_agent.toggle()
  end, { desc = 'Toggle Cursor Agent terminal' })

  vim.api.nvim_create_user_command('CursorAgentVersion', function()
    local version = require('cursoragent.version').string()
    vim.notify('cursoragent.nvim version: ' .. version, vim.log.levels.INFO)
  end, { desc = 'Display cursoragent.nvim version' })

  vim.api.nvim_create_user_command('CursorAgentPrompt', function()
    local util = require('cursoragent.util')
    util.notify('CursorAgentPrompt is deprecated; use :CursorAgent', vim.log.levels.WARN)
    cursor_agent.toggle()
  end, { desc = 'Deprecated: use :CursorAgent' })

  vim.api.nvim_create_user_command('CursorAgentSelection', function()
    local context = require('cursoragent.context')
    local util = require('cursoragent.util')
    local sel = context.get_visual_selection()
    if not sel or sel == '' then
      util.notify('No visual selection', vim.log.levels.WARN)
      return
    end
    local tmp = util.write_tempfile(sel, '.txt')
    cursor_agent.ask({ file = tmp, title = 'Selection → Cursor Agent' })
  end, { range = true, desc = 'Send current visual selection to Cursor Agent' })

  vim.api.nvim_create_user_command('CursorAgentBuffer', function()
    local context = require('cursoragent.context')
    local util = require('cursoragent.util')
    local bufctx = context.get_buffer_context()
    local title = ('%s → Cursor Agent'):format(vim.fn.fnamemodify(bufctx.filepath, ':t'))
    local tmp = util.write_tempfile(bufctx.content, '.txt')
    cursor_agent.ask({ file = tmp, title = title })
  end, { desc = 'Send current buffer contents to Cursor Agent' })

  -- Register variant commands if command_variants exists (backward compatibility)
  -- Note: In new config structure, variants are handled via terminal.open() with cmd_args
  if cursor_agent.config and cursor_agent.config.command_variants then
    for variant_name, variant_args in pairs(cursor_agent.config.command_variants) do
      if variant_args ~= false then
        local capitalized_name = variant_name:gsub('^%l', string.upper)
        local cmd_name = 'CursorAgent' .. capitalized_name

        vim.api.nvim_create_user_command(cmd_name, function()
          if cursor_agent.toggle_with_variant then
            cursor_agent.toggle_with_variant(variant_name)
          else
            -- Fallback: use terminal.open() with cmd_args
            local terminal = require("cursoragent.terminal")
            terminal.open(nil, variant_args)
          end
        end, { desc = 'Toggle Cursor Agent terminal with ' .. variant_name .. ' option' })
      end
    end
  end
end

return M

