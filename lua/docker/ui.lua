local Config = require("docker.config")

local UI = {}

---@class DockerUIHandlers
---@field on_select fun(container: DockerContainer)|nil
---@field on_start fun(container: DockerContainer)|nil
---@field on_stop fun(container: DockerContainer)|nil
---@field on_restart fun(container: DockerContainer)|nil
---@field on_close fun()|nil

local highlight_namespace = vim.api.nvim_create_namespace("nvim-docker")
local close_augroup = vim.api.nvim_create_augroup("NvimDockerClose", {
    clear = true,
})
local is_closing = false
local current_mode = nil
local current_containers = {}
local current_handlers = {}
local previous_guicursor = nil

local windows = {
    containers = nil,
    logs = nil,
    footer = nil,
}

local buffers = {
    containers = nil,
    logs = nil,
    footer = nil,
}

---@return nil
local function reset_state()
    windows.containers = nil
    windows.logs = nil
    windows.footer = nil

    buffers.containers = nil
    buffers.logs = nil
    buffers.footer = nil

    current_mode = nil
    current_containers = {}
    current_handlers = {}
end

---@param window integer|nil
---@return nil
local function close_window(window)
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end
end

---@return nil
function UI.close()
    if is_closing then
        return
    end

    is_closing = true

    vim.api.nvim_clear_autocmds({
        group = close_augroup,
    })

    local on_close = current_handlers.on_close

    close_window(windows.containers)
    close_window(windows.logs)
    close_window(windows.footer)

    if previous_guicursor then
        vim.o.guicursor = previous_guicursor
        previous_guicursor = nil
    end

    reset_state()

    if on_close then
        on_close()
    end

    is_closing = false
end

---@return integer
local function create_buffer()
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].filetype = "nvim-docker"

    return buffer
end

---@param value number
---@param total integer
---@return integer
local function resolve_size(value, total)
    if value <= 1 then
        return math.floor(total * value)
    end

    return math.floor(value)
end

---@param mode "docker"|"compose"
---@return string
local function get_containers_title(mode)
    if mode == "compose" then
        return " Docker Compose "
    end

    return " Docker "
end

---@param container DockerContainer
---@return string
local function get_status_type(container)
    if container.state == "running" then
        return "running"
    end

    if container.state == "restarting" then
        return "restarting"
    end

    if container.state == "exited" then
        local exit_code = container.status:match("Exited %((%-?%d+)%)")

        if exit_code and tonumber(exit_code) ~= 0 then
            return "failed"
        end

        return "stopped"
    end

    if container.state == "dead" then
        return "failed"
    end

    if container.state == "created" or container.state == "paused" then
        return "stopped"
    end

    return "unknown"
end

---@param value string
---@param maximum_width integer
---@param ellipsis string
---@return string
local function truncate(value, maximum_width, ellipsis)
    if vim.fn.strdisplaywidth(value) <= maximum_width then
        return value
    end

    local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)

    if maximum_width <= ellipsis_width then
        return vim.fn.strcharpart(ellipsis, 0, maximum_width)
    end

    return vim.fn.strcharpart(
        value,
        0,
        maximum_width - ellipsis_width
    ) .. ellipsis
end

---@param value string
---@param width integer
---@return string
local function pad_right(value, width)
    local padding = math.max(0, width - vim.fn.strdisplaywidth(value))

    return value .. string.rep(" ", padding)
end

---@param mode "docker"|"compose"
---@param config DockerConfig
---@return string[]
local function get_columns(mode, config)
    if mode == "compose" then
        return config.containers.compose_columns
    end

    return config.containers.docker_columns
end

---@param container DockerContainer
---@param column string
---@return string
local function get_column_value(container, column)
    local value = container[column]

    if value == nil or value == "" then
        return "-"
    end

    return tostring(value)
end

---@param columns string[]
---@param widths DockerColumnWidthsConfig
---@param ellipsis string
---@param container DockerContainer|nil
---@return string
local function build_columns_line(columns, widths, ellipsis, container)
    local values = {}

    for _, column in ipairs(columns) do
        local width = widths[column]

        if width then
            local value = column:upper()

            if container then
                value = get_column_value(container, column)
            end

            value = truncate(value, width, ellipsis)

            table.insert(values, pad_right(value, width))
        end
    end

    return table.concat(values, " ")
end

---@param mode "docker"|"compose"
---@param containers DockerContainer[]
---@return string[]
---@return table[]
local function build_container_lines(mode, containers)
    local config = Config.get()
    local columns = get_columns(mode, config)
    local widths = config.containers.column_widths
    local ellipsis = config.containers.ellipsis
    local lines = {}
    local highlights = {}

    table.insert(
        lines,
        "  " .. build_columns_line(columns, widths, ellipsis, nil)
    )

    if #containers == 0 then
        table.insert(lines, "")
        table.insert(lines, "  No containers found.")

        return lines, highlights
    end

    for index, container in ipairs(containers) do
        local status_type = get_status_type(container)
        local icon = config.status_icons[status_type]
        local highlight = config.status_highlights[status_type]
        local columns_line = build_columns_line(
            columns,
            widths,
            ellipsis,
            container
        )

        table.insert(lines, icon .. " " .. columns_line)

        table.insert(highlights, {
            line = index,
            group = highlight,
            start_column = 0,
            end_column = #icon,
        })
    end

    return lines, highlights
end

---@param buffer integer
---@param lines string[]
---@return nil
local function set_buffer_lines(buffer, lines)
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
end

---@param highlights table[]
---@return nil
local function apply_container_highlights(highlights)
    vim.api.nvim_buf_clear_namespace(
        buffers.containers,
        highlight_namespace,
        0,
        -1
    )

    for _, highlight in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(
            buffers.containers,
            highlight_namespace,
            highlight.line,
            highlight.start_column,
            {
                end_col = highlight.end_column,
                hl_group = highlight.group,
            }
        )
    end
end

---@return DockerContainer|nil
local function get_container_under_cursor()
    if not windows.containers
        or not vim.api.nvim_win_is_valid(windows.containers)
    then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(windows.containers)
    local container_index = cursor[1] - 1

    if container_index < 1 then
        return nil
    end

    return current_containers[container_index]
end

---@param container DockerContainer
---@return nil
local function show_container_details(container)
    set_buffer_lines(buffers.logs, {
        "",
        "  Selected container",
        "",
        "  Name:    " .. get_column_value(container, "name"),
        "  Service: " .. get_column_value(container, "service"),
        "  Image:   " .. get_column_value(container, "image"),
        "  State:   " .. get_column_value(container, "state"),
        "  Status:  " .. get_column_value(container, "status"),
        "  Ports:   " .. get_column_value(container, "ports"),
        "  ID:      " .. get_column_value(container, "id"),
        "",
        "  Live logs will be displayed here.",
    })
end

---@param handler_name "on_select"|"on_start"|"on_stop"|"on_restart"
---@return nil
local function run_container_handler(handler_name)
    local container = get_container_under_cursor()

    if not container then
        return
    end

    if handler_name == "on_select" then
        show_container_details(container)
    end

    local handler = current_handlers[handler_name]

    if handler then
        handler(container)
    end
end

---@return nil
local function focus_containers()
    if windows.containers
        and vim.api.nvim_win_is_valid(windows.containers)
    then
        vim.api.nvim_set_current_win(windows.containers)
    end
end

---@return nil
local function focus_logs()
    if windows.logs and vim.api.nvim_win_is_valid(windows.logs) then
        vim.api.nvim_set_current_win(windows.logs)
    end
end

---@return nil
local function configure_windows()
    vim.wo[windows.containers].cursorline = true
    vim.wo[windows.containers].number = false
    vim.wo[windows.containers].relativenumber = false
    vim.wo[windows.containers].signcolumn = "no"
    vim.wo[windows.containers].wrap = false

    vim.wo[windows.logs].number = false
    vim.wo[windows.logs].relativenumber = false
    vim.wo[windows.logs].signcolumn = "no"
    vim.wo[windows.logs].wrap = false

    vim.wo[windows.footer].number = false
    vim.wo[windows.footer].relativenumber = false
    vim.wo[windows.footer].signcolumn = "no"
    vim.wo[windows.footer].cursorline = false
    vim.wo[windows.footer].winhighlight = "Normal:Comment,FloatBorder:FloatBorder"
end

---@param buffer integer
---@return nil
local function set_close_keymap(buffer)
    local options = {
        buffer = buffer,
        silent = true,
        nowait = true,
        desc = "Close nvim-docker",
    }

    vim.keymap.set("n", "<Esc>", UI.close, options)
    vim.keymap.set("n", "q", UI.close, options)
end

---@return nil
local function set_container_keymaps()
    vim.keymap.set("n", "<Enter>", function()
        run_container_handler("on_select")
    end, {
        buffer = buffers.containers,
        silent = true,
        desc = "Select Docker container",
    })

    vim.keymap.set("n", "s", function()
        run_container_handler("on_start")
    end, {
        buffer = buffers.containers,
        silent = true,
        desc = "Start Docker container",
    })

    vim.keymap.set("n", "x", function()
        run_container_handler("on_stop")
    end, {
        buffer = buffers.containers,
        silent = true,
        desc = "Stop Docker container",
    })

    vim.keymap.set("n", "r", function()
        run_container_handler("on_restart")
    end, {
        buffer = buffers.containers,
        silent = true,
        desc = "Restart Docker container",
    })

    vim.keymap.set("n", "<Tab>", focus_logs, {
        buffer = buffers.containers,
        silent = true,
        desc = "Focus Docker logs",
    })
end

---@return nil
local function set_logs_keymaps()
    vim.keymap.set("n", "<Tab>", focus_containers, {
        buffer = buffers.logs,
        silent = true,
        desc = "Focus Docker containers",
    })
end

---@return nil
local function set_keymaps()
    set_close_keymap(buffers.containers)
    set_close_keymap(buffers.logs)
    set_close_keymap(buffers.footer)

    set_container_keymaps()
    set_logs_keymaps()
end

---@param window integer
---@return boolean
local function is_plugin_window(window)
    return window == windows.containers
        or window == windows.logs
        or window == windows.footer
end

---@return nil
local function close_when_focus_leaves()
    vim.api.nvim_clear_autocmds({
        group = close_augroup,
    })

    vim.api.nvim_create_autocmd("WinEnter", {
        group = close_augroup,
        callback = function()
            vim.schedule(function()
                local current_window = vim.api.nvim_get_current_win()

                if not is_plugin_window(current_window) then
                    UI.close()
                end
            end)
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = close_augroup,
        callback = function(event)
            local closed_window = tonumber(event.match)

            if closed_window and is_plugin_window(closed_window) then
                vim.schedule(UI.close)
            end
        end,
    })
end

---@return nil
local function keep_cursor_on_containers()
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = close_augroup,
        buffer = buffers.containers,
        callback = function()
            local cursor = vim.api.nvim_win_get_cursor(windows.containers)

            if cursor[1] < 2 and #current_containers > 0 then
                vim.api.nvim_win_set_cursor(windows.containers, { 2, cursor[2] })
            end
        end,
    })
end

---@param containers DockerContainer[]
---@return nil
function UI.update_containers(containers)
    if not current_mode
        or not buffers.containers
        or not vim.api.nvim_buf_is_valid(buffers.containers)
        or not windows.containers
        or not vim.api.nvim_win_is_valid(windows.containers)
    then
        return
    end

    local selected_container = get_container_under_cursor()
    local selected_container_id = selected_container and selected_container.id or nil
    local current_cursor = vim.api.nvim_win_get_cursor(windows.containers)
    local current_index = math.max(1, current_cursor[1] - 1)

    current_containers = containers

    local container_lines, highlights = build_container_lines(
        current_mode,
        current_containers
    )

    set_buffer_lines(buffers.containers, container_lines)
    apply_container_highlights(highlights)

    if #current_containers == 0 then
        vim.api.nvim_win_set_cursor(windows.containers, { 1, 0 })

        return
    end

    local selected_index = nil

    if selected_container_id then
        for index, container in ipairs(current_containers) do
            if container.id == selected_container_id then
                selected_index = index

                break
            end
        end
    end

    selected_index = selected_index or math.min(
        current_index,
        #current_containers
    )

    vim.api.nvim_win_set_cursor(
        windows.containers,
        { selected_index + 1, 0 }
    )
end

---@param mode "docker"|"compose"
---@param containers DockerContainer[]
---@param handlers DockerUIHandlers|nil
---@return nil
function UI.open(mode, containers, handlers)
    UI.close()

    previous_guicursor = vim.o.guicursor
    vim.o.guicursor = "n-v-c:ver25,i-ci-ve:ver25,r-cr:hor20,o:hor50"

    current_mode = mode
    current_containers = containers
    current_handlers = handlers or {}

    local config = Config.get()

    local editor_width = vim.o.columns
    local editor_height = vim.o.lines - vim.o.cmdheight

    local total_width = resolve_size(config.window.width, editor_width)
    local total_height = resolve_size(config.window.height, editor_height)

    total_width = math.max(total_width, 60)
    total_height = math.max(total_height, 12)

    local footer_height = 1
    local panels_height = total_height - footer_height - 2

    local containers_width = math.floor(
        total_width * config.window.containers_width
    )
    local logs_width = total_width - containers_width - 2

    containers_width = math.max(containers_width, 28)
    logs_width = math.max(logs_width, 28)

    local row = math.floor((editor_height - total_height) / 2)
    local column = math.floor((editor_width - total_width) / 2)

    buffers.containers = create_buffer()
    buffers.logs = create_buffer()
    buffers.footer = create_buffer()

    windows.containers = vim.api.nvim_open_win(buffers.containers, true, {
        relative = "editor",
        row = row,
        col = column,
        width = containers_width,
        height = panels_height,
        style = "minimal",
        border = "rounded",
        title = get_containers_title(mode),
        title_pos = "center",
    })

    windows.logs = vim.api.nvim_open_win(buffers.logs, false, {
        relative = "editor",
        row = row,
        col = column + containers_width + 2,
        width = logs_width,
        height = panels_height,
        style = "minimal",
        border = "rounded",
        title = " Logs ",
        title_pos = "center",
    })

    windows.footer = vim.api.nvim_open_win(buffers.footer, false, {
        relative = "editor",
        row = row + panels_height + 2,
        col = column,
        width = total_width,
        height = footer_height,
        style = "minimal",
        border = "rounded",
    })

    configure_windows()
    set_keymaps()
    close_when_focus_leaves()
    keep_cursor_on_containers()

    local container_lines, highlights = build_container_lines(
        mode,
        containers
    )

    set_buffer_lines(buffers.containers, container_lines)
    set_buffer_lines(buffers.logs, {
        "",
        "  Select a container to view its logs.",
    })
    set_buffer_lines(buffers.footer, {
        "  Enter logs   s start   x stop   r restart   Tab switch panel   G follow logs   Esc/q close",
    })

    apply_container_highlights(highlights)

    if #containers > 0 then
        vim.api.nvim_win_set_cursor(windows.containers, { 2, 0 })
    end
end

return UI
