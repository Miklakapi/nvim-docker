local Config = {}

---@class DockerWindowConfig
---@field width number
---@field height number
---@field containers_width number

---@class DockerLogsConfig
---@field tail number
---@field auto_select boolean

---@class DockerStatusIconsConfig
---@field running string
---@field restarting string
---@field stopped string
---@field failed string
---@field unknown string

---@class DockerStatusHighlightsConfig
---@field running string
---@field restarting string
---@field stopped string
---@field failed string
---@field unknown string

---@class DockerConfig
---@field window DockerWindowConfig
---@field logs DockerLogsConfig
---@field status_icons DockerStatusIconsConfig
---@field status_highlights DockerStatusHighlightsConfig

---@type DockerConfig
local default_config = {
    window = {
        width = 0.9,
        height = 0.85,
        containers_width = 0.35,
    },
    logs = {
        tail = 200,
        auto_select = true,
    },
    status_icons = {
        running = "●",
        restarting = "◐",
        stopped = "○",
        failed = "×",
        unknown = "?",
    },
    status_highlights = {
        running = "DiagnosticOk",
        restarting = "DiagnosticWarn",
        stopped = "Comment",
        failed = "DiagnosticError",
        unknown = "DiagnosticInfo",
    },
}

---@type DockerConfig
local current_config = vim.deepcopy(default_config)

---@param user_config DockerConfig|nil
---@return nil
function Config.setup(user_config)
    current_config = vim.tbl_deep_extend(
        "force",
        vim.deepcopy(default_config),
        user_config or {}
    )
end

---@return DockerConfig config
function Config.get()
    return current_config
end

return Config
