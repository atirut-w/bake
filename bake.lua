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
        print("Bakefile not found")
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
        if macro:match(" ") then
            local command = macro:match("^([^ ]+)")
            local args = macro:match("^[^ ]+%s+(.*)")

            ---@param value any
            ---@param cases table<any, function>
            local function switch(value, cases)
                return (cases[value] or (cases.default or function() end))()
            end

            local cmd_result = switch(command, {
                default = function()
                    print("Unknown macro: " .. macro)
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
                print("Unknown macro: " .. macro)
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
        if not line:match("^#") then
            local target_name, dependencies = line:match("^([^:]+):(.*)")
            if target_name then
                current_target = #targets + 1
                targets[current_target] = {
                    name = target_name,
                    dependencies = {},
                    commands = {}
                }
                
                for dependency in dependencies:gmatch("[^ ]+") do
                    table.insert(targets[current_target].dependencies, dependency)
                end
            elseif current_target then
                if line:match("^%s") then
                    table.insert(targets[current_target].commands, line:match("^%s*(.*)"))
                else
                    current_target = nil
                end
            else
                -- TODO: Optimize pattern matching
                local macro_name, macro_value = line:match("^([^=]+)=(.*)")
                macro_name = macro_name:match("^%s*(.-)%s*$")
                macro_value = macro_value:match("^%s*(.-)%s*$")

                if macro_name then
                    macros[macro_name] = resolve_macros(macro_value)
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
    print("Target not found: " .. name)
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
local function run_target(target)
    for _,dependency in ipairs(target.dependencies) do
        run_target(get_target(dependency))
    end
    for _,command in ipairs(target.commands) do
        run(command)
    end
end

if #targets == 0 then
    print("No targets defined")
    os.exit(1)
else
    if args.target then
        run_target(get_target(args.target))
    else
        run_target(targets[1])
    end
end
