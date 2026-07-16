local Config = require("docker.config")
local UI = require("docker.ui")

local Docker = {}

---@param user_config DockerConfig|nil
---@return nil
function Docker.setup(user_config)
    Config.setup(user_config)

    vim.api.nvim_create_user_command("Docker", function()
        -- Future flow:
        -- 1. Fetch all Docker containers.
        -- 2. Open the UI with the current container list.
        -- 3. Start listening for Docker events.
        -- 4. Update the UI when the container state changes.
        UI.open("docker")
    end, {
        desc = "Open Docker containers",
        force = true,
    })

    vim.api.nvim_create_user_command("DockerCompose", function()
        -- Future flow:
        -- 1. Detect the current Docker Compose project.
        -- 2. Fetch containers belonging to that project.
        -- 3. Open the UI with the project container list.
        -- 4. Start listening for project-related Docker events.
        -- 5. Update the UI when the container state changes.
        UI.open("compose")
    end, {
        desc = "Open Docker Compose project containers",
        force = true,
    })
end

return Docker
