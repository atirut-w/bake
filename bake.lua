local fs = require("filesystem")
local shell = require("shell")

local xprint = require("xprint")

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
---@field update_time number
---@field dependencies table<integer, string>
---@field commands table<integer, string>

local macros = {}
---@type table<string, MakeTarget>
local targets = {}
---@type table<integer, string>
local targets_ordering = {}

--- Metadata for targets (such as .PHONY). This is kept separate from the
--- targets table to allow metadata to be defined independently (even for
--- targets that don't exist).
---@type table<string, table>
local targets_metadata = setmetatable({}, {
    __index = function(t, k)
        local new_entry = {}
        t[k] = new_entry
        return new_entry
    end
})

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
                    return "@echo '" .. args .. "'"
                end,
                shell = function()
                    local stream = io.popen(args)
                    local result = stream:read("a")
                    if result then
                        result = result:gsub("\n", " ")
                    end
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
    ---@type string
    local current_targets = nil
    ---@type string
    local current_dependencies = nil
    ---@type table<integer, string>
    local last_target_commands = {}

    --- Builds a new target using data stored in current_targets,
    --- current_dependencies and last_target_commands
    local function add_targets()
        for target_name in current_targets:gmatch("%S+") do
            if targets[target_name] then
                io.stderr:write("bake: Found multiple definitions for target \'" .. target_name .. "\'.\n")
                os.exit(1)
            end
            local new_target = {
                update_time = -1,
                dependencies = {},
                commands = {}
            }
            targets[target_name] = new_target
            targets_ordering[#targets_ordering + 1] = target_name

            for dependency in current_dependencies:gmatch("%S+") do
                table.insert(new_target.dependencies, dependency)
            end
            for i, command in ipairs(last_target_commands) do
                new_target.commands[i] = command
            end
        end
    end

    -- Iterate each line in file (skipping any that begin with '#' character or
    -- only whitespace). Check line for macros, target definitions, or commands
    for line in bakefile_content:gmatch("[^\r\n]+") do
        if not line:match("^#") and line:match("%S") then
            if line:find("%s") ~= 1 then
                if current_targets then
                    add_targets()
                    current_targets = nil
                    current_dependencies = nil
                    last_target_commands = {}
                end
                line = resolve_macros(line)

                -- TODO: Optimize pattern matching
                local macro_name, macro_value = line:match("^([^=]+)=(.*)")
                if macro_name then
                    -- Trim whitespace
                    macro_name = macro_name:match("^%s*(.-)%s*$")
                    macro_value = macro_value:match("^%s*(.-)%s*$")

                    macros[macro_name] = macro_value
                else
                    local target_names, dependencies = line:match("^([^:]+):(.*)")

                    if target_names then
                        if target_names:match("^%.PHONY%s*$") then
                            for target_name in dependencies:gmatch("%S+") do
                                targets_metadata[target_name].phony = true
                            end
                        else
                            current_targets = target_names
                            current_dependencies = dependencies
                        end
                    end
                end
            elseif current_targets then
                table.insert(last_target_commands, line:match("^%s*(.*)"))
            end
        end
    end
    if current_targets then
        add_targets()
    end

    print("finished file scan")
    xprint({}, "macros", macros, "targets", targets, "targets_metadata", targets_metadata)
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

--- All of the dependency targets touched thus far (basically functions like a
--- stack of the dependencies)
---@type table<MakeTarget, boolean>
local traversed_targets = {}

--- Run a target. Returns the file modification time if applicable, or math.huge
--- to indicate that the target updated.
---@param target_name string
---@param is_first boolean
---@return number
local function run_target(target_name, is_first)
    -- Find the target from the name (it may not be found, or it could be an
    -- existing file)
    local target = targets[target_name]
    local target_path = shell.resolve(target_name)
    if not target then
        if not fs.exists(target_path) and not targets_metadata[target_name].phony then
            io.stderr:write("bake: Target not found: " .. target_name .. "\n")
            os.exit(1)
        elseif is_first then
            print("bake: Nothing to be done for \'" .. target_name .. "\'.")
        end
        if targets_metadata[target_name].phony then
            return math.huge
        else
            return fs.lastModified(target_path)
        end
    end

    if traversed_targets[target] then
        -- Cyclic dependency found
        return -1
    end
    if target.update_time ~= -1 then
        -- Do not run a given target more than once
        return target.update_time
    end
    traversed_targets[target] = true

    if fs.exists(target_path) and not targets_metadata[target_name].phony then
        target.update_time = fs.lastModified(target_path)
    else
        target.update_time = math.huge
    end

    -- Create a space-separated list of each dependency, and another for just
    -- the dependencies that changed for the target
    local all_dependencies = ""
    local updated_dependencies = ""
    for _,dependency in ipairs(target.dependencies) do
        local update_time = run_target(dependency, false)
        if update_time == -1 then
            print("bake: Circular " .. target_name .. " <- " .. dependency .. " dependency dropped.")
        end
        all_dependencies = all_dependencies .. dependency .. " "
        if update_time == math.huge or target.update_time == math.huge or update_time > target.update_time then
            updated_dependencies = updated_dependencies .. dependency .. " "
        end
    end
    all_dependencies = all_dependencies:sub(1, -2)
    updated_dependencies = updated_dependencies:sub(1, -2)

    -- Finished dependencies for this target, remove the traversed_targets entry
    -- so we don't mark it as a cycle in another target
    traversed_targets[target] = nil

    -- Only run the target if no corresponding file found, or dependency updated
    if target.update_time == math.huge or #updated_dependencies > 0 then
        local automaticVars = {
            ["@"] = target_name,
            ["?"] = updated_dependencies,
            ["^"] = all_dependencies
        }
        for _,command in ipairs(target.commands) do
            run(command:gsub("%$([@?^])", automaticVars))
        end
        return math.huge
    elseif is_first then
        print("bake: \'" .. target_name .. "\' is up to date.")
    end

    return target.update_time
end

if #targets_ordering == 0 then
    io.stderr:write("bake: No targets defined\n")
    os.exit(1)
else
    if args.target then
        run_target(args.target, true)
    else
        run_target(targets_ordering[1], true)
    end
end
