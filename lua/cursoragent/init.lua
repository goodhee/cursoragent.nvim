---@mod cursoragent Cursor Agent Neovim Plugin
---@brief [[
--- A Neovim plugin for seamless integration with Cursor Agent CLI.
--- Provides terminal-based interface with multi-instance support, file refresh,
--- and various window configurations.
---@brief ]]

local config = require('cursoragent.config')
local context = require('cursoragent.context')
local util = require('cursoragent.util')
local terminal = require('cursoragent.terminal')
local file_refresh = require('cursoragent.file_refresh')
local git = require('cursoragent.git')
local commands = require('cursoragent.commands')
local termui = require('cursoragent.ui.term')
local logger = require('cursoragent.logger')

local M = {}

M.commands = commands
M.config = {}
-- M.terminal removed: use terminal module functions directly (terminal.get_active_terminal_bufnr(), etc.)

-- Module state for MCP server and selection tracking
M.state = {
  config = nil,
  server = nil,
  port = nil,
  auth_token = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
}

---Clear the mention queue and stop any pending timer
local function clear_mention_queue()
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
  else
    if #M.state.mention_queue > 0 then
      logger.debug("queue", "Clearing " .. #M.state.mention_queue .. " queued @ mentions")
    end
    M.state.mention_queue = {}
  end

  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
    M.state.mention_timer = nil
  end
end

---Process mentions when Cursor Agent is connected (debounced mode)
local function process_connected_mentions()
  -- Reset the debounce timer
  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
  end

  -- Set a new timer to process the queue after 50ms of inactivity
  M.state.mention_timer = vim.loop.new_timer()
  local debounce_delay = math.max(10, 50) -- Minimum 10ms debounce, 50ms for batching

  -- Use vim.schedule_wrap if available, otherwise fallback to vim.schedule + function call
  local wrapped_function = vim.schedule_wrap and vim.schedule_wrap(M.process_mention_queue)
    or function()
      vim.schedule(M.process_mention_queue)
    end

  M.state.mention_timer:start(debounce_delay, 0, wrapped_function)
end

---Start connection timeout timer if not already started
local function start_connection_timeout_if_needed()
  if not M.state.connection_timer then
    M.state.connection_timer = vim.loop.new_timer()
    M.state.connection_timer:start(M.state.config.connection_timeout, 0, function()
      vim.schedule(function()
        if #M.state.mention_queue > 0 then
          logger.error("queue", "Connection timeout - clearing " .. #M.state.mention_queue .. " queued @ mentions")
          clear_mention_queue()
        end
      end)
    end)
  end
end

---Add @ mention to queue
---@param file_path string The file path to mention
---@param start_line number|nil Optional start line
---@param end_line number|nil Optional end line
local function queue_mention(file_path, start_line, end_line)
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
  end

  local mention_data = {
    file_path = file_path,
    start_line = start_line,
    end_line = end_line,
    timestamp = vim.loop.now(),
  }

  table.insert(M.state.mention_queue, mention_data)
  logger.debug("queue", "Queued @ mention: " .. file_path .. " (queue size: " .. #M.state.mention_queue .. ")")

  -- Process based on connection state
  if M.is_connected() then
    -- Connected: Use debounced processing
    process_connected_mentions()
  else
    -- Disconnected: Start connection timeout timer
    start_connection_timeout_if_needed()
  end
end

---Process the mention queue (handles both connected and disconnected modes)
---@param from_new_connection boolean|nil Whether this is triggered by a new connection (adds delay)
function M.process_mention_queue(from_new_connection)
  -- Initialize mention_queue if it doesn't exist (for test compatibility)
  if not M.state.mention_queue then
    M.state.mention_queue = {}
    return
  end

  if #M.state.mention_queue == 0 then
    return
  end

  if not M.is_connected() then
    -- Still disconnected or handshake not complete yet, wait for readiness
    logger.debug("queue", "Cursor Agent not ready (no handshake). Keeping ", #M.state.mention_queue, " mentions queued")

    -- If triggered by a new connection, poll until handshake completes (bounded by connection_timeout timer)
    if from_new_connection then
      local retry_delay = math.max(50, math.floor((M.state.config.connection_wait_delay or 200) / 4))
      vim.defer_fn(function()
        M.process_mention_queue(true)
      end, retry_delay)
    end
    return
  end

  local mentions_to_send = vim.deepcopy(M.state.mention_queue)
  M.state.mention_queue = {} -- Clear queue

  -- Stop any existing timer
  if M.state.mention_timer then
    M.state.mention_timer:stop()
    M.state.mention_timer:close()
    M.state.mention_timer = nil
  end

  -- Stop connection timer since we're now connected
  if M.state.connection_timer then
    M.state.connection_timer:stop()
    M.state.connection_timer:close()
    M.state.connection_timer = nil
  end

  logger.debug("queue", "Processing " .. #mentions_to_send .. " queued @ mentions")

  -- Send mentions with a small delay between each to prevent WebSocket/extension overwhelm
  local function send_mention_sequential(index)
    if index > #mentions_to_send then
      logger.debug("queue", "All queued mentions sent successfully")
      return
    end

    local mention = mentions_to_send[index]

    -- Check if mention has expired (same timeout logic as old system)
    local current_time = vim.loop.now()
    if (current_time - mention.timestamp) > M.state.config.queue_timeout then
      logger.debug("queue", "Skipped expired @ mention: " .. mention.file_path)
    else
      -- Directly broadcast without going through the queue system to avoid infinite recursion
      local params = {
        filePath = mention.file_path,
        lineStart = mention.start_line,
        lineEnd = mention.end_line,
      }

      local broadcast_success = M.state.server.broadcast("at_mentioned", params)
      if broadcast_success then
        logger.debug("queue", "Sent queued @ mention: " .. mention.file_path)
      else
        logger.error("queue", "Failed to send queued @ mention: " .. mention.file_path)
      end
    end

    -- Process next mention with delay
    if index < #mentions_to_send then
      local inter_message_delay = 25 -- ms
      vim.defer_fn(function()
        send_mention_sequential(index + 1)
      end, inter_message_delay)
    end
  end

  -- Apply delay for new connections, send immediately for debounced processing
  if #mentions_to_send > 0 then
    if from_new_connection then
      -- Wait for connection_wait_delay when processing queue after new connection
      local initial_delay = (M.state.config and M.state.config.connection_wait_delay) or 200
      logger.debug("queue", "Waiting ", initial_delay, "ms after connect before flushing queue")
      vim.defer_fn(function()
        send_mention_sequential(1)
      end, initial_delay)
    else
      -- Send immediately for debounced processing (Cursor Agent already connected)
      send_mention_sequential(1)
    end
  end
end

function M.force_insert_mode()
  -- Get active terminal buffer and enter insert mode
  local bufnr = terminal.get_active_terminal_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      local win = wins[1]
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        if vim.bo[bufnr].buftype == "terminal" and vim.fn.mode() == "n" then
          vim.cmd("startinsert")
        end
      end
    end
  end
end

local function get_current_buffer_number()
  -- Use the new terminal provider pattern
  return terminal.get_active_terminal_bufnr()
end

function M.toggle()
  terminal.simple_toggle()
end

---Toggle the cursoragent terminal window with a specific command variant
---@param variant_name string The name of the command variant to use
function M.toggle_with_variant(variant_name)
  if not variant_name or not M.config.command_variants[variant_name] then
    -- If variant doesn't exist, fall back to regular toggle
    return M.toggle()
  end

  local original_command = M.config.command
  local variant_args = M.config.command_variants[variant_name]
  if not variant_args or variant_args == false then
    return M.toggle()
  end

  -- variant_args를 문자열로 변환
  local cmd_args = type(variant_args) == "string" and variant_args or nil

  terminal.simple_toggle(nil, cmd_args)
end

---Ask cursoragent with a prompt or file
---@param opts table Options table
---@field file string|nil File path to send
---@field prompt string|nil Prompt text to send
---@field title string|nil Window title
function M.ask(opts)
  opts = opts or {}
  local title = opts.title or 'Cursor Agent'
  local command = (M.state.config and M.state.config.terminal_cmd) or 'cursor-agent'
  if not command or command == '' then
	  command = 'cursor-agent'
  end

  local argv = vim.split(command, '%s+', { trimempty = true })
  if not argv or #argv == 0 then
    util.err('Invalid command configured')
    return
  end

  if opts.file and opts.file ~= '' then
    table.insert(argv, opts.file)
  elseif opts.prompt and opts.prompt ~= '' then
    table.insert(argv, opts.prompt)
  end

  local root = util.get_project_root()
  termui.open_float_term({
    argv = argv,
    title = title,
    border = 'rounded',
    width = 0.6,
    height = 0.6,
    cwd = root,
    on_exit = function(code)
      if code ~= 0 then
        util.notify(('cursoragent exited with code %d'):format(code), vim.log.levels.WARN)
      end
    end,
  })
end

function M.toggle_terminal()
  M.toggle()
end

---Return the plugin version string (e.g. "0.1.0")
---@return string version
function M.version()
  return require("cursoragent.version").string()
end

---Setup function for the plugin
---@param user_config? table User configuration table (optional)
function M.setup(user_config)
  user_config = user_config or {}

  -- Apply configuration (claude-code.nvim style)
  M.state.config = config.apply(user_config)
  M.config = M.state.config

  -- Setup logger
  logger.setup(M.state.config)

  -- Setup terminal module: always try to call setup to pass terminal_cmd and env,
  -- even if terminal_opts (for split_side etc.) are not provided.
  -- Map top-level cwd-related aliases into terminal config for convenience
  do
    local t = user_config.terminal or {}
    local had_alias = false
    if user_config.git_repo_cwd ~= nil then
      t.git_repo_cwd = user_config.git_repo_cwd
      had_alias = true
    end
    if user_config.cwd ~= nil then
      t.cwd = user_config.cwd
      had_alias = true
    end
    if user_config.cwd_provider ~= nil then
      t.cwd_provider = user_config.cwd_provider
      had_alias = true
    end
    if had_alias then
      user_config.terminal = t
    end
  end

  local terminal_setup_ok, terminal_module = pcall(require, "cursoragent.terminal")
  if terminal_setup_ok then
    -- Guard in case tests or user replace the module with a minimal stub without `setup`.
    if type(terminal_module.setup) == "function" then
      -- terminal_opts might be nil, which the setup function should handle gracefully.
      terminal_module.setup(user_config.terminal, M.state.config.terminal_cmd, M.state.config.env)
    end
  else
    logger.error("init", "Failed to load cursoragent.terminal module for setup.")
  end

  -- Setup diff module
  local diff = require("cursoragent.diff")
  if diff and diff.setup then
    diff.setup(M.state.config)
  end

  -- Auto-start MCP server if configured
  if M.state.config.auto_start then
    M.start(false) -- Suppress notification on auto-start
  end

  -- Register commands
  commands.register_commands(M)

  -- Register keymaps (opt-out via config.keymaps.* = false)
  local keymaps_ok, keymaps = pcall(require, "cursoragent.keymaps")
  if keymaps_ok and keymaps.register_keymaps then
    keymaps.register_keymaps(M, M.state.config)
  else
    logger.error("init", "Failed to load cursoragent.keymaps module for setup.")
  end

  -- Setup VimLeavePre autocmd to stop server on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("CursorAgentShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      else
        -- Clear queue even if server isn't running
        clear_mention_queue()
      end
    end,
    desc = "Automatically stop Cursor Agent integration when exiting Neovim",
  })

  -- Legacy: Keep file_refresh for backward compatibility
  -- Only setup if old config structure is present
  if M.config.refresh then
    vim.o.autoread = true
    file_refresh.setup(M, M.config)
  end

  M.state.initialized = true
  return M
end

---Start the Cursor Agent MCP server
---@param show_startup_notification? boolean Whether to show a notification upon successful startup (defaults to true)
---@return boolean success Whether the operation was successful
---@return number|string port_or_error The WebSocket port if successful, or error message if failed
function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end
  if M.state.server then
    local msg = "Cursor Agent integration is already running on port " .. tostring(M.state.port)
    logger.warn("init", msg)
    return false, "Already running"
  end

  local server = require("cursoragent.server.init")
  local lockfile = require("cursoragent.lockfile")

  -- Generate auth token first so we can pass it to the server
  local auth_token
  local auth_success, auth_result = pcall(function()
    return lockfile.generate_auth_token()
  end)

  if not auth_success then
    local error_msg = "Failed to generate authentication token: " .. (auth_result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  auth_token = auth_result

  -- Validate the generated auth token
  if not auth_token or type(auth_token) ~= "string" or #auth_token < 10 then
    local error_msg = "Invalid authentication token generated"
    logger.error("init", error_msg)
    return false, error_msg
  end

  -- Prepare server config with port_range from config
  local server_config = {
    port_range = M.state.config.port_range or { min = 10000, max = 65535 },
  }

  local success, result = server.start(server_config, auth_token)

  if not success then
    local error_msg = "Failed to start Cursor Agent server: " .. (result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  M.state.server = server
  M.state.port = tonumber(result)
  M.state.auth_token = auth_token

  local lock_success, lock_result, returned_auth_token = lockfile.create(M.state.port, auth_token)

  if not lock_success then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Failed to create lock file: " .. (lock_result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  -- Verify that the auth token in the lock file matches what we generated
  if returned_auth_token ~= auth_token then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Authentication token mismatch between server and lock file"
    logger.error("init", error_msg)
    return false, error_msg
  end

  -- Enable selection tracking if configured
  if M.state.config.track_selection then
    local selection = require("cursoragent.selection")
    if selection and selection.enable then
      local visual_demotion_delay_ms = M.state.config.visual_demotion_delay_ms or 50
      selection.enable(M.state.server, visual_demotion_delay_ms)
    end
  end

  if show_startup_notification then
    logger.info("init", "Cursor Agent integration started on port " .. tostring(M.state.port))
  end

  return true, M.state.port
end

---Stop the Cursor Agent MCP server
---@return boolean success Whether the operation was successful
---@return string|nil error Error message if operation failed
function M.stop()
  if not M.state.server then
    logger.warn("init", "Cursor Agent integration is not running")
    return false, "Not running"
  end

  -- Disable selection tracking
  local selection = require("cursoragent.selection")
  if selection and selection.disable then
    selection.disable()
  end

  local lockfile = require("cursoragent.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)

  if not lock_success then
    logger.warn("init", "Failed to remove lock file: " .. lock_error)
    -- Continue with shutdown even if lock file removal fails
  end

  M.state.server.stop()
  M.state.server = nil
  M.state.port = nil
  M.state.auth_token = nil

  clear_mention_queue()

  logger.info("init", "Cursor Agent integration stopped")
  return true, nil
end

---Check if Cursor Agent is connected to MCP server
---@return boolean connected Whether Cursor Agent has active connections
function M.is_connected()
  if not M.state.server then
    return false
  end

  local server_module = require("cursoragent.server.init")
  local status = server_module.get_status()
  if not status or not status.running then
    return false
  end

  -- Check if there are connected clients
  if status.clients and #status.clients > 0 then
    for _, info in ipairs(status.clients) do
      if (info.state == "connected" or info.handshake_complete == true) and info.handshake_complete == true then
        return true
      end
    end
    return false
  else
    return status.client_count and status.client_count > 0
  end
end

---Send @ mention to Cursor Agent, handling connection state automatically
---@param file_path string The file path to send
---@param start_line number|nil Start line (0-indexed for Cursor Agent)
---@param end_line number|nil End line (0-indexed for Cursor Agent)
---@param context string|nil Context for logging
---@return boolean success Whether the operation was successful
---@return string|nil error Error message if failed
function M.send_at_mention(file_path, start_line, end_line, context)
  context = context or "command"

  if not M.state.server then
    logger.error(context, "Cursor Agent integration is not running")
    return false, "Cursor Agent integration is not running"
  end

  -- Check if Cursor Agent is connected
  if M.is_connected() then
    -- Cursor Agent is connected, send immediately and ensure terminal is visible
    local params = {
      filePath = file_path,
      lineStart = start_line,
      lineEnd = end_line,
    }

    local broadcast_success = M.state.server.broadcast("at_mentioned", params)
    if broadcast_success then
      logger.debug(context, "Sent @ mention: " .. file_path)
      local terminal = require("cursoragent.terminal")
      if M.state.config and M.state.config.focus_after_send then
        -- Open focuses the terminal without toggling/hiding if already focused
        terminal.open()
      end
      return true, nil
    else
      logger.error(context, "Failed to send @ mention: " .. file_path)
      return false, "Failed to broadcast"
    end
  else
    -- Not connected: queue the mention
    queue_mention(file_path, start_line, end_line)

    -- Launch terminal with Cursor Agent
    local terminal = require("cursoragent.terminal")
    terminal.open()

    -- Always return success since we're queuing the message
    -- The actual broadcast result will be logged in the queue processing
    return true, nil
  end
end

return M

