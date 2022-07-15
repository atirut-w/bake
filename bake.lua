local fs = require("filesystem")
local shell = require("shell")

---@type table<string, any>
local args = {}
do
    local raw_args = {...}
    
    if raw_args[1] == "-h" or raw_args[1] == "--help" then
        print("Usage: bake [target]")
        os.exit(0)
    else
        args.target = raw_args[1]
    end
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

local bakefile_content
do
    ---@type file*
    local file
    if exists("Bakefile") then
        file = io.open("Bakefile", "r")
    elseif exists("bakefile") then
        file = io.open("bakefile", "r")
    else
        io.stderr:write("bake: Bakefile not found\n")
        os.exit(1)
    end
    bakefile_content = file:read("a")
end

---@class MakeTarget
---@field name string
---@field dependencies table<integer, string>
---@field commands table<integer, string>

local macros = {}
---@type table<string, MakeTarget>
local targets = {}

--- Resolve macros and commands
---@param text string
---@return string
local function resolve_macros(text)
    for macro in text:gmatch("%$%(([^%)]+)%)") do
        if macro:match("%s") then
            local command = macro:match("^(%S+)")
            local args = macro:match("^%S+%s+(.*)")

            ---@param value any
            ---@param cases table<any, function>
            local function switch(value, cases)
                return (cases[value] or (cases.default or function() end))()
            end

            local cmd_result = switch(command, {
                default = function()
                    io.stderr:write("bake: Unknown macro: " .. macro .. "\n")
                    return nil
                end,
                info = function()
                    return "echo '" .. args .. "'"
                end,
                shell = function()
                    local stream = io.popen(args)
                    local result = stream:read("a")
                    stream:close()
                    return result
                end,
            })

            if cmd_result then
                text = text:gsub("%$%(" .. macro .. "%)", cmd_result)
            end
        else
            if macros[macro] then
                text = text:gsub("%$%(" .. macro .. "%)", macros[macro])
            else
                io.stderr:write("bake: Unknown macro: " .. macro .. "\n")
                os.exit(1)
            end
        end
    end

    return text
end

do
    ---@type integer
    local current_target = nil
    for line in bakefile_content:gmatch("[^\r\n]+") do
        if not line:match("^#") and line:match("%S") then
            local target_name, dependencies = line:match("^([^%s:]+):(.*)")
            if target_name then
                current_target = #targets + 1
                targets[current_target] = {
                    name = target_name,
                    update_time = -1,
                    dependencies = {},
                    commands = {}
                }
                
                for dependency in dependencies:gmatch("%S+") do
                    table.insert(targets[current_target].dependencies, dependency)
                end
            else
                -- TODO: Optimize pattern matching
                local macro_name, macro_value = line:match("^([^=]+)=(.*)")
                if macro_name then
                    -- Trim whitespace
                    macro_name = macro_name:match("^%s*(.-)%s*$")
                    macro_value = macro_value:match("^%s*(.-)%s*$")

                    macros[macro_name] = resolve_macros(macro_value)
                elseif current_target and line:match("^%s") then
                    table.insert(targets[current_target].commands, line:match("^%s*(.*)"))
                else
                    current_target = nil
                end
            end
        end
    end
end

--- Get a target by name
---@param name string
---@return MakeTarget
local function get_target(name)
    for _, target in pairs(targets) do
        if target.name == name then
            return target
        end
    end
    io.stderr:write("bake: Target not found: " .. name .. "\n")
    os.exit(1)
end

--- Run a command
---@param command string
local function run(command)
    command = resolve_macros(command)
    if command:sub(1,1) == "@" then
        command = command:sub(2)
    else
        print(command)
    end
    os.execute(command)
end

--- Run a target
---@param target MakeTarget
---@param is_first boolean
---@return number
local function run_target(target, is_first)
    if target.update_time ~= -1 then
        -- Do not run a given target more than once
        return target.update_time
    end

    -- Find greatest modification timestamp of all dependency files
    local depend_update_time = -1
    for _,dependency in ipairs(target.dependencies) do
        depend_update_time = math.max(depend_update_time, run_target(get_target(dependency), false))
    end

    local target_path = shell.resolve(target.name)
    if fs.exists(target_path) then
        target.update_time = fs.lastModified(target_path)
    else
        target.update_time = math.huge
    end

    -- Only run the target if no corresponding file found, or dependency updated
    if target.update_time == math.huge or depend_update_time > target.update_time then
        for _,command in ipairs(target.commands) do
            run(command)
        end
        return math.huge
    elseif is_first then
        print("bake: \'" .. target.name .. "\' is up to date.")
    end

    return target.update_time
end

if #targets == 0 then
    io.stderr:write("bake: No targets defined\n")
    os.exit(1)
else
    if args.target then
        run_target(get_target(args.target), true)
    else
        run_target(targets[1], true)
    end
end
