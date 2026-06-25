local M = {}

function M.open()
    vim.cmd("botright 12split")

    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(0, buffer)

    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = true

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "nvim-docker",
        "",
        "This will be the main Docker panel.",
        "",
        "For now it is only a simple split buffer."
    })

    vim.bo[buffer].modifiable = false
end

return M
