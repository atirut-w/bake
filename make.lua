---@type table<string, any>
local args
do
    local argparse = require("argparse")
    local parser = argparse("make", "A reimplementation of Make in Lua")

    parser:argument("target", "The target to build")

    args = parser:parse({...})
end

--- Check if a file exists
---@param path string
---@return boolean
local function exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

local makefile_content
do
    ---@type file*
    local file
    if exists("Makefile") then
        file = io.open("Makefile", "r")
    elseif exists("makefile") then
        file = io.open("makefile", "r")
    else
        print("Makefile not found")
        os.exit(1)
    end
    makefile_content = file:read("a")
end
