local Config = require("docker.config")
local UI = require("docker.ui")
local DockerClient = require("docker.docker")

local Docker = {}

---@param user_config DockerConfig|nil
---@return nil
function Docker.setup(user_config)
    Config.setup(user_config)

    vim.api.nvim_create_user_command("Docker", function()
        DockerClient.list_containers(function(containers, error_message)
            if error_message then
                vim.notify(error_message, vim.log.levels.ERROR)

                return
            end

            vim.print(containers)

            -- Future flow:
            -- 1. Open the UI with the current container list.
            -- 2. Start listening for Docker events.
            -- 3. Update the UI when the container state changes.
            --
            -- UI.open("docker", containers)
        end)
    end, {
        desc = "Open Docker containers",
        force = true,
    })

    vim.api.nvim_create_user_command("DockerCompose", function()
        DockerClient.list_compose_containers(function(containers, error_message)
            if error_message then
                vim.notify(error_message, vim.log.levels.ERROR)

                return
            end

            vim.print(containers)

            -- Future flow:
            -- 1. Open the UI with the current project container list.
            -- 2. Start listening for project-related Docker events.
            -- 3. Update the UI when the container state changes.
            --
            -- UI.open("compose", containers)
        end)
    end, {
        desc = "Open Docker Compose project containers",
        force = true,
    })
end

return Docker
