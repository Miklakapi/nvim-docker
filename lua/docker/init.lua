local Config = require("docker.config")
local DockerClient = require("docker.docker")
local UI = require("docker.ui")

local Docker = {}

---@param action string
---@param container DockerContainer
---@param callback fun(container_id: string, callback: DockerActionCallback)
---@return nil
local function run_action(action, container, callback)
    callback(container.id, function(error_message)
        if error_message then
            vim.notify(error_message, vim.log.levels.ERROR)

            return
        end

        vim.notify(
            string.format("%s container: %s", action, container.name),
            vim.log.levels.INFO
        )
    end)
end

---@return DockerUIHandlers
local function create_ui_handlers()
    return {
        on_select = function(container)
            vim.notify(
                "Selected container: " .. container.name,
                vim.log.levels.INFO
            )
        end,

        on_start = function(container)
            run_action("Started", container, DockerClient.start_container)
        end,

        on_stop = function(container)
            run_action("Stopped", container, DockerClient.stop_container)
        end,

        on_restart = function(container)
            run_action("Restarted", container, DockerClient.restart_container)
        end,
    }
end

---@param containers DockerContainer[]|nil
---@param error_message string|nil
---@param mode "docker"|"compose"
---@return nil
local function open_ui(containers, error_message, mode)
    if error_message then
        vim.notify(error_message, vim.log.levels.ERROR)

        return
    end

    UI.open(mode, containers or {}, create_ui_handlers())
end

---@param user_config DockerConfig|nil
---@return nil
function Docker.setup(user_config)
    Config.setup(user_config)

    vim.api.nvim_create_user_command("Docker", function()
        DockerClient.list_containers(function(containers, error_message)
            open_ui(containers, error_message, "docker")
        end)
    end, {
        desc = "Open Docker containers",
        force = true,
    })

    vim.api.nvim_create_user_command("DockerCompose", function()
        DockerClient.list_compose_containers(function(containers, error_message)
            open_ui(containers, error_message, "compose")
        end)
    end, {
        desc = "Open Docker Compose project containers",
        force = true,
    })
end

return Docker
