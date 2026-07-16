local Config = require("docker.config")
local UI = require("docker.ui")

local Docker = {}

---@param user_config DockerConfig|nil
---@return nil
function Docker.setup(user_config)
    Config.setup(user_config)

    vim.api.nvim_create_user_command("Docker", function()
        UI.open("docker")
    end, {
        desc = "Open Docker containers",
        force = true,
    })

    vim.api.nvim_create_user_command("DockerCompose", function()
        UI.open("compose")
    end, {
        desc = "Open Docker Compose project containers",
        force = true,
    })
end

return Docker
