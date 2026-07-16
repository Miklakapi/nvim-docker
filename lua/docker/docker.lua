local Docker = {}

---@class DockerContainer
---@field id string
---@field name string
---@field service string
---@field image string
---@field state string
---@field status string
---@field health string
---@field ports string

---@alias DockerMode "docker"|"compose"
---@alias DockerContainersCallback fun(containers: DockerContainer[]|nil, error_message: string|nil)
---@alias DockerActionCallback fun(error_message: string|nil)
---@alias DockerWatchStop fun()

---@param publishers table[]|nil
---@return string
local function format_publishers(publishers)
    if not publishers then
        return ""
    end

    local ports = {}

    for _, publisher in ipairs(publishers) do
        local target_port = publisher.TargetPort
        local published_port = publisher.PublishedPort
        local protocol = publisher.Protocol or "tcp"
        local url = publisher.URL

        if published_port and published_port > 0 then
            local address = url and url ~= "" and url .. ":" or ""

            table.insert(
                ports,
                string.format(
                    "%s%s->%s/%s",
                    address,
                    published_port,
                    target_port,
                    protocol
                )
            )
        elseif target_port then
            table.insert(ports, string.format("%s/%s", target_port, protocol))
        end
    end

    return table.concat(ports, ", ")
end

---@param value unknown
---@return string
local function normalize_string(value)
    if value == nil then
        return ""
    end

    return tostring(value)
end

---@param container table
---@return DockerContainer
local function normalize_container(container)
    local ports = container.Ports

    if type(container.Publishers) == "table" then
        ports = format_publishers(container.Publishers)
    end

    return {
        id = normalize_string(container.ID),
        name = normalize_string(container.Names or container.Name),
        service = normalize_string(container.Service),
        image = normalize_string(container.Image),
        state = normalize_string(container.State):lower(),
        status = normalize_string(container.Status or container.State),
        health = normalize_string(container.Health):lower(),
        ports = normalize_string(ports),
    }
end

---@param output string
---@return DockerContainer[]|nil containers
---@return string|nil error_message
local function parse_containers(output)
    local containers = {}
    local lines = vim.split(output, "\n", {
        trimempty = true,
    })

    for _, line in ipairs(lines) do
        local success, decoded = pcall(vim.json.decode, line)

        if not success then
            return nil, "Failed to parse Docker container data"
        end

        table.insert(containers, normalize_container(decoded))
    end

    return containers, nil
end

---@param command string[]
---@param options table|nil
---@param callback DockerContainersCallback
---@return nil
local function execute_list_command(command, options, callback)
    vim.system(command, vim.tbl_extend("force", {
        text = true,
    }, options or {}), function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local error_message = vim.trim(result.stderr or "")

                if error_message == "" then
                    error_message = "Docker command failed with exit code " .. result.code
                end

                callback(nil, error_message)

                return
            end

            local containers, error_message = parse_containers(result.stdout or "")

            callback(containers, error_message)
        end)
    end)
end

---@param action "start"|"stop"|"restart"
---@param container_id string
---@param callback DockerActionCallback
---@return nil
local function execute_container_action(action, container_id, callback)
    vim.system({
        "docker",
        action,
        container_id,
    }, {
        text = true,
    }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local error_message = vim.trim(result.stderr or "")

                if error_message == "" then
                    error_message = string.format(
                        "Docker %s failed with exit code %d",
                        action,
                        result.code
                    )
                end

                callback(error_message)

                return
            end

            callback(nil)
        end)
    end)
end

---@param mode DockerMode
---@param callback DockerContainersCallback
---@return nil
local function fetch_containers(mode, callback)
    if mode == "compose" then
        Docker.list_compose_containers(callback)

        return
    end

    Docker.list_containers(callback)
end

---@param callback DockerContainersCallback
---@return nil
function Docker.list_containers(callback)
    execute_list_command({
        "docker",
        "ps",
        "--all",
        "--no-trunc",
        "--format",
        "json",
    }, nil, callback)
end

---@param callback DockerContainersCallback
---@return nil
function Docker.list_compose_containers(callback)
    execute_list_command({
        "docker",
        "compose",
        "ps",
        "--all",
        "--format",
        "json",
    }, {
        cwd = vim.fn.getcwd(),
    }, callback)
end

---@param container_id string
---@param callback DockerActionCallback
---@return nil
function Docker.start_container(container_id, callback)
    execute_container_action("start", container_id, callback)
end

---@param container_id string
---@param callback DockerActionCallback
---@return nil
function Docker.stop_container(container_id, callback)
    execute_container_action("stop", container_id, callback)
end

---@param container_id string
---@param callback DockerActionCallback
---@return nil
function Docker.restart_container(container_id, callback)
    execute_container_action("restart", container_id, callback)
end

---@param mode DockerMode
---@param callback DockerContainersCallback
---@return DockerWatchStop
function Docker.watch_containers(mode, callback)
    local timer = vim.uv.new_timer()
    local is_stopped = false
    local is_refreshing = false

    local function refresh()
        if is_stopped or is_refreshing then
            return
        end

        is_refreshing = true

        fetch_containers(mode, function(containers, error_message)
            is_refreshing = false

            if is_stopped then
                return
            end

            callback(containers, error_message)
        end)
    end

    if not timer then
        callback(nil, "Failed to create Docker watcher")

        return function()
            is_stopped = true
        end
    end

    timer:start(0, 2000, vim.schedule_wrap(refresh))

    return function()
        if is_stopped then
            return
        end

        is_stopped = true
        timer:stop()

        if not timer:is_closing() then
            timer:close()
        end
    end
end

return Docker
