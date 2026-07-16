local UI = {}

---@param mode "docker"|"compose"
---@return nil
function UI.open(mode)
    vim.notify("Opening nvim-docker in " .. mode .. " mode")
end

return UI
