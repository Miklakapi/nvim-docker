local Config = require("docker.config")

local UI = {}

local highlight_namespace = vim.api.nvim_create_namespace("nvim-docker")
local close_augroup = vim.api.nvim_create_augroup("NvimDockerClose", {
    clear = true,
})
local is_closing = false

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

    close_window(windows.containers)
    close_window(windows.logs)
    close_window(windows.footer)

    reset_state()

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
local function set_keymaps()
    set_close_keymap(buffers.containers)
    set_close_keymap(buffers.logs)
    set_close_keymap(buffers.footer)
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

---@param mode "docker"|"compose"
---@param containers DockerContainer[]
---@return nil
function UI.open(mode, containers)
    UI.close()

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
