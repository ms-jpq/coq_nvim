local M = {}

-- Merge content of two table and returns a new table
function M.merge_tables(t1, t2)
    for k, v in pairs(t2) do
        if (type(v) == 'table') and (type(t1[k] or false) == 'table') then
            M.merge_tables(t1[k], t2[k])
        else
            t1[k] = v
        end
    end

    return t1
end

function M.get_script_path()
    local str = debug.getinfo(2, 'S').source:sub(2)
    return str:match('(.*)/lua')
end

function M.seek_rtp()
    local name = 'coq_nvim'
    for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
        if string.sub(rtp, -(#name)) == name then return rtp end
    end
    assert(false, 'RTP NOT FOUND')
end

return M
