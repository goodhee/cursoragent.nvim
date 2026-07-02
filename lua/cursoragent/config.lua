---@brief [[
--- Manages configuration for the Cursor Agent Neovim integration.
--- Provides default settings, validation, and application of user-defined configurations.
---@brief ]]
---@module 'cursoragent.config'

local M = {}

---@type CursorAgentConfig
M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  env = {}, -- Custom environment variables for Cursor Agent terminal
  log_level = "info",
  track_selection = true,
  -- When true, focus Cursor Agent terminal after a successful send while connected
  focus_after_send = false,
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 600, -- Milliseconds to wait after connection before sending queued @ mentions
  connection_timeout = 10000, -- Maximum time to wait for Cursor Agent to connect (milliseconds)
  queue_timeout = 5000, -- Maximum time to keep @ mentions in queue (milliseconds)
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false, -- Open diff in a new tab (false = use current tab)
    keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens
    hide_terminal_in_new_tab = false, -- If true and opening in a new tab, do not show Cursor Agent terminal there
    on_new_file_reject = "keep_empty", -- "keep_empty" leaves an empty buffer; "close_window" closes the placeholder split
  },
  -- Keymaps (conventional defaults; set any entry to false to disable)
  keymaps = {
    toggle = {
      normal = "<C-,>", -- Normal mode keymap for toggling Cursor Agent, false to disable
      terminal = "<C-,>", -- Terminal mode keymap for toggling Cursor Agent, false to disable
      variants = {}, -- Per-variant normal mode keymaps, e.g. { ask = "<leader>caa" }
    },
    window_navigation = true, -- Enable <C-h/j/k/l> window navigation from the terminal
    scrolling = true, -- Enable <C-f/b> page scrolling in the terminal
  },
  terminal = nil, -- Will be lazy-loaded to avoid circular dependency
}

---Validates the provided configuration table.
---Throws an error if any validation fails.
---@param config table The configuration table to validate.
---@return boolean true if the configuration is valid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  -- Validate terminal config
  assert(type(config.terminal) == "table", "terminal must be a table")

  -- Validate provider_opts if present
  if config.terminal.provider_opts then
    assert(type(config.terminal.provider_opts) == "table", "terminal.provider_opts must be a table")

    -- Validate external_terminal_cmd in provider_opts
    if config.terminal.provider_opts.external_terminal_cmd then
      local cmd_type = type(config.terminal.provider_opts.external_terminal_cmd)
      assert(
        cmd_type == "string" or cmd_type == "function",
        "terminal.provider_opts.external_terminal_cmd must be a string or function"
      )
      -- Only validate %s placeholder for strings
      if cmd_type == "string" and config.terminal.provider_opts.external_terminal_cmd ~= "" then
        assert(
          config.terminal.provider_opts.external_terminal_cmd:find("%%s"),
          "terminal.provider_opts.external_terminal_cmd must contain '%s' placeholder for the Cursor Agent command"
        )
      end
    end
  end

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")
  -- Allow absence in direct validate() calls; apply() supplies default
  if config.focus_after_send ~= nil then
    assert(type(config.focus_after_send) == "boolean", "focus_after_send must be a boolean")
  end

  assert(
    type(config.visual_demotion_delay_ms) == "number" and config.visual_demotion_delay_ms >= 0,
    "visual_demotion_delay_ms must be a non-negative number"
  )

  assert(
    type(config.connection_wait_delay) == "number" and config.connection_wait_delay >= 0,
    "connection_wait_delay must be a non-negative number"
  )

  assert(
    type(config.connection_timeout) == "number" and config.connection_timeout > 0,
    "connection_timeout must be a positive number"
  )

  assert(type(config.queue_timeout) == "number" and config.queue_timeout > 0, "queue_timeout must be a positive number")

  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  -- New diff options (optional validation to allow backward compatibility)
  if config.diff_opts.layout ~= nil then
    assert(
      config.diff_opts.layout == "vertical" or config.diff_opts.layout == "horizontal",
      "diff_opts.layout must be 'vertical' or 'horizontal'"
    )
  end
  if config.diff_opts.open_in_new_tab ~= nil then
    assert(type(config.diff_opts.open_in_new_tab) == "boolean", "diff_opts.open_in_new_tab must be a boolean")
  end
  if config.diff_opts.keep_terminal_focus ~= nil then
    assert(type(config.diff_opts.keep_terminal_focus) == "boolean", "diff_opts.keep_terminal_focus must be a boolean")
  end
  if config.diff_opts.hide_terminal_in_new_tab ~= nil then
    assert(
      type(config.diff_opts.hide_terminal_in_new_tab) == "boolean",
      "diff_opts.hide_terminal_in_new_tab must be a boolean"
    )
  end
  if config.diff_opts.on_new_file_reject ~= nil then
    assert(
      type(config.diff_opts.on_new_file_reject) == "string"
        and (
          config.diff_opts.on_new_file_reject == "keep_empty" or config.diff_opts.on_new_file_reject == "close_window"
        ),
      "diff_opts.on_new_file_reject must be 'keep_empty' or 'close_window'"
    )
  end

  -- Legacy diff options (accept if present to avoid breaking old configs)
  if config.diff_opts.auto_close_on_accept ~= nil then
    assert(type(config.diff_opts.auto_close_on_accept) == "boolean", "diff_opts.auto_close_on_accept must be a boolean")
  end
  if config.diff_opts.show_diff_stats ~= nil then
    assert(type(config.diff_opts.show_diff_stats) == "boolean", "diff_opts.show_diff_stats must be a boolean")
  end
  if config.diff_opts.vertical_split ~= nil then
    assert(type(config.diff_opts.vertical_split) == "boolean", "diff_opts.vertical_split must be a boolean")
  end
  if config.diff_opts.open_in_current_tab ~= nil then
    assert(type(config.diff_opts.open_in_current_tab) == "boolean", "diff_opts.open_in_current_tab must be a boolean")
  end

  -- Validate keymaps (optional; only checked when present)
  if config.keymaps ~= nil then
    assert(type(config.keymaps) == "table", "keymaps must be a table")
    if config.keymaps.toggle ~= nil then
      assert(type(config.keymaps.toggle) == "table", "keymaps.toggle must be a table")
      local t = config.keymaps.toggle
      assert(
        t.normal == nil or t.normal == false or type(t.normal) == "string",
        "keymaps.toggle.normal must be a string or false"
      )
      assert(
        t.terminal == nil or t.terminal == false or type(t.terminal) == "string",
        "keymaps.toggle.terminal must be a string or false"
      )
      if t.variants ~= nil then
        assert(type(t.variants) == "table", "keymaps.toggle.variants must be a table")
        for name, key in pairs(t.variants) do
          assert(type(name) == "string", "keymaps.toggle.variants keys must be strings")
          assert(
            key == false or type(key) == "string",
            "keymaps.toggle.variants values must be a string or false"
          )
        end
      end
    end
    if config.keymaps.window_navigation ~= nil then
      assert(type(config.keymaps.window_navigation) == "boolean", "keymaps.window_navigation must be a boolean")
    end
    if config.keymaps.scrolling ~= nil then
      assert(type(config.keymaps.scrolling) == "boolean", "keymaps.scrolling must be a boolean")
    end
  end

  -- Validate env
  assert(type(config.env) == "table", "env must be a table")
  for key, value in pairs(config.env) do
    assert(type(key) == "string", "env keys must be strings")
    assert(type(value) == "string", "env values must be strings")
  end

  return true
end

---Applies user configuration on top of default settings and validates the result.
---Also handles backward compatibility with old config structure.
---@param user_config table|nil The user-provided configuration table.
---@return CursorAgentConfig config The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  -- Lazy-load terminal defaults to avoid circular dependency
  if config.terminal == nil then
    local terminal_ok, terminal_module = pcall(require, "cursoragent.terminal")
    if terminal_ok and terminal_module.defaults then
      config.terminal = terminal_module.defaults
    end
  end

  if user_config then
    -- Backward compatibility: Convert old config structure to new structure
    local converted_config = {}
    
    -- Convert old mcp.* to top-level fields
    if user_config.mcp then
      if user_config.mcp.port_range then
        converted_config.port_range = user_config.mcp.port_range
      end
      if user_config.mcp.auto_start ~= nil then
        converted_config.auto_start = user_config.mcp.auto_start
      end
      if user_config.mcp.log_level then
        converted_config.log_level = user_config.mcp.log_level
      end
      if user_config.mcp.track_selection ~= nil then
        converted_config.track_selection = user_config.mcp.track_selection
      end
      if user_config.mcp.focus_after_send ~= nil then
        converted_config.focus_after_send = user_config.mcp.focus_after_send
      end
      if user_config.mcp.visual_demotion_delay_ms then
        converted_config.visual_demotion_delay_ms = user_config.mcp.visual_demotion_delay_ms
      end
      if user_config.mcp.connection_wait_delay then
        converted_config.connection_wait_delay = user_config.mcp.connection_wait_delay
      end
      if user_config.mcp.connection_timeout then
        converted_config.connection_timeout = user_config.mcp.connection_timeout
      end
      if user_config.mcp.queue_timeout then
        converted_config.queue_timeout = user_config.mcp.queue_timeout
      end
      if user_config.mcp.diff_opts then
        converted_config.diff_opts = user_config.mcp.diff_opts
      end
    end
    
    -- Convert old command to terminal_cmd
    if user_config.command then
      -- Extract base command (remove subcommands like "ask", "plan", etc.)
      local cmd = user_config.command
      -- Remove common subcommands and options
      cmd = cmd:gsub("%s+ask%s*", " ")
      cmd = cmd:gsub("%s+plan%s*", " ")
      cmd = cmd:gsub("%s+agent%s*", " ")
      cmd = cmd:gsub("%s+%-%-resume%s*", " ")
      cmd = cmd:gsub("%s+%-%-model%s+%S+%s*", " ")
      cmd = vim.trim(cmd)
      if cmd ~= "" then
        converted_config.terminal_cmd = cmd
    end
  end
  
    -- Convert old window.* to terminal.*
    if user_config.window then
      converted_config.terminal = converted_config.terminal or {}
      if user_config.window.position then
        -- Map position to split_side
        if user_config.window.position:match("right") or user_config.window.position:match("botright") then
          converted_config.terminal.split_side = "right"
        elseif user_config.window.position:match("left") or user_config.window.position:match("topleft") then
          converted_config.terminal.split_side = "left"
        end
      end
      if user_config.window.split_ratio then
        converted_config.terminal.split_width_percentage = user_config.window.split_ratio
    end
  end
  
    -- Merge converted config with user config (user config takes precedence)
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, converted_config, user_config)
    else
      -- Simple fallback for testing environment
      for k, v in pairs(converted_config) do
        if config[k] == nil or type(config[k]) ~= "table" then
          config[k] = v
        else
          for k2, v2 in pairs(v) do
            config[k][k2] = v2
          end
        end
      end
      for k, v in pairs(user_config) do
        if config[k] == nil or type(config[k]) ~= "table" then
          config[k] = v
        else
          for k2, v2 in pairs(v) do
            config[k][k2] = v2
          end
        end
      end
    end
  end
  
  -- Backward compatibility: map legacy diff options to new fields if provided
  if config.diff_opts then
    local d = config.diff_opts
    -- Map vertical_split -> layout (legacy option takes precedence)
    if type(d.vertical_split) == "boolean" then
      d.layout = d.vertical_split and "vertical" or "horizontal"
    end
    -- Map open_in_current_tab -> open_in_new_tab (legacy option takes precedence)
    if type(d.open_in_current_tab) == "boolean" then
      d.open_in_new_tab = not d.open_in_current_tab
    end
  end

  M.validate(config)

  return config
end

return M
