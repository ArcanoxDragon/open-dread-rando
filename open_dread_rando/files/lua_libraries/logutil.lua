logutil = {
    nextId = 0,
    messageContainer = nil,
    messages = {},
}

Game.LogWarn(0, "Loading logutil.lua")

local MAX_MESSAGES = 40
local LINE_HEIGHT = 0.02
local MESSAGE_LIFETIME = 30
local MESSAGE_FADE_TIME = 0.3
local LEVEL_COLORS = {
    default = { ColorR = 1.0, ColorG = 1.0, ColorB = 1.0, ColorA = 1.0 },
    D = { ColorR = 0.2, ColorG = 1.0, ColorB = 1.0, ColorA = 1.0 },
    W = { ColorR = 1.0, ColorG = 1.0, ColorB = 0.2, ColorA = 1.0 },
    E = { ColorR = 1.0, ColorG = 0.2, ColorB = 0.2, ColorA = 1.0 },
}

setmetatable(LEVEL_COLORS, { __index = function() return LEVEL_COLORS["default"] end})

Init.DEBUG = true
Game.ExtraDebugAllowed = function() return true end
Game.VersionNumberAllowed = function() return true end
Game.MemoryStatsAllowed = function() return true end

local Game_Log_Original = Game.Log
local Game_LogWarn_Original = Game.LogWarn
local Game_LogError_Original = Game.LogError
local print_Original = print

local LogMessage = {}
LogMessage.__index = LogMessage

function LogMessage.Create(level, text)
    local obj = {
        id = logutil.GetNextId(),
        level = level,
        text = text,
    }

    local colors = LEVEL_COLORS[level]

    for k, v in pairs(colors) do
        colors[k] = tostring(v)
    end

    local msgName = "LogMessage" .. obj.id

    obj.root = GUI.CreateDisplayObjectEx(msgName, "CDisplayObjectContainer", { StageID = "Up", X = "0.0", Y = "0.0", SizeX = "1.0", SizeY = tostring(LINE_HEIGHT + 0.04), ScaleX = "1.0", ScaleY = "1.0", ColorA = "1.0" })
    obj.level = GUI.CreateDisplayObject(obj.root, msgName .. "_Level", "CLabel", { StageID = "Up", X = "0.02", Y = "0.02", ScaleX = "1.0", ScaleY = "1.0", Font = "digital_small", TextAlignment = "Left", Text = level })
    obj.text = GUI.CreateDisplayObject(obj.root, msgName .. "_Text", "CLabel", { StageID = "Up", X = "0.04", Y = "0.02", ScaleX = "1.0", ScaleY = "1.0", Font = "digital_small", TextAlignment = "Left", Text = string.gsub(text, "|", "l") })

    GUI.SetProperties(obj.level, colors)
    GUI.SetProperties(obj.text, colors)
    GUI.SetHierarchyProperties(obj.root, { Enabled = true, Visible = true })

    setmetatable(obj, LogMessage)

    return obj
end

function LogMessage:Destroy()
    GUI.DestroyDisplayObject(self.root)
end

function LogMessage:SetPosition(line)
    GUI.SetHierarchyProperties(self.root, { Y = tostring(1.0 - LINE_HEIGHT * (line + 2)) })
end

function LogMessage:FadeOut(time)
    time = time or MESSAGE_FADE_TIME

    GUI.SetProperties(self.root, { FadeColorR = "-1.0", FadeColorG = "-1.0", FadeColorB = "-1.0", FadeColorA = "0.0", FadeTime = tostring(time) })
    Game.AddSF(time, "logutil.PopMessage", "i", self.id)
end

function logutil.main()
    Game.AddSF(0.1, "logutil.main_Delayed", "")
end

function logutil.main_Delayed()
    -- Pop all messages when loading begins
    local old_guicallbacks_OnLoadScenarioRequest = guicallbacks.OnLoadScenarioRequest
    guicallbacks.OnLoadScenarioRequest = function(...)
        old_guicallbacks_OnLoadScenarioRequest()
        logutil.PopAllMessages()
    end

    local root = GUI.GetDisplayObject("[Root]")

    if logutil.messages then
        for i = 1, #logutil.messages do
            if logutil.messages[i] then
                logutil.messages[i]:Destroy()
            end
        end
    end

    if logutil.messageContainer then
        GUI.DestroyDisplayObject(logutil.messageContainer)
    end

    logutil.messages = {}
    logutil.messageContainer = GUI.CreateDisplayObjectEx("MessageContainer", "CDisplayObjectContainer", {
        Enabled = true,
        Visible = true,
        X = "0.0",
        Y = "0.0",
        SizeX = "2.0",
        SizeY = "2.0",
        ScaleX = "0.5",
        ScaleY = "0.5",
        Angle = "0.0",
        ColorR = "1.0",
        ColorG = "1.0",
        ColorB = "1.0",
        ColorA = "1.0",
    })
    root:AddChild(logutil.messageContainer)

    Game.Log = function(_, message)
        Game_Log_Original(_, message)
        logutil.Log("D", message)
    end
    Game.LogWarn = function(_, message)
        Game_LogWarn_Original(_, message)
        logutil.Log("W", message)
    end
    Game.LogError = function(_, message)
        Game_LogError_Original(_, message)
        logutil.Log("E", message)
    end

    _G.print = function(message)
        logutil.Log("D", message)
        print_Original(message)
    end
end

function logutil.Log(level, format, ...)
    local text = tostring(format):format(...)
    local message = LogMessage.Create(level, text)

    if #logutil.messages >= MAX_MESSAGES then
        logutil.PopOldestMessage()
    end

    table.insert(logutil.messages, 1, message)
    logutil.messageContainer:AddChild(message.root)

    Game.AddSF(0.1, "logutil.RepositionMessages", "")
    Game.AddSF(MESSAGE_LIFETIME, "logutil.FadeMessage", "i", message.id)
end

function logutil.RepositionMessages()
    for i = 1, #logutil.messages do
        if logutil.messages[i] then
            logutil.messages[i]:SetPosition(i)
        end
    end
end

function logutil.GetNextId()
    local nextId = logutil.nextId

    logutil.nextId = logutil.nextId + 1

    return nextId
end

function logutil.GetMessage(id)
    for i = 1, #logutil.messages do
        if logutil.messages[i] and logutil.messages[i].id == id then
            return logutil.messages[i], i
        end
    end

    return nil, -1
end

function logutil.PopMessageAt(index)
    if #logutil.messages < index then
        return
    end

    for i = index, #logutil.messages do
        if i == index and logutil.messages[i] then
            -- This one is getting popped off, so destroy it
            logutil.messages[i]:Destroy()
        end

        logutil.messages[i] = logutil.messages[i + 1]
    end

    Game.AddSF(0.1, "logutil.RepositionMessages", "")
end

function logutil.PopMessage(id)
    local message, index = logutil.GetMessage(id)

    if not message then
        return
    end

    logutil.PopMessageAt(index)
end

function logutil.FadeMessage(id, time)
    time = time or MESSAGE_FADE_TIME

    local message = logutil.GetMessage(id)

    if not message then
        return
    end

    message:FadeOut(time)
end

function logutil.PopOldestMessage()
    logutil.PopMessageAt(#logutil.messages)
end

function logutil.PopAllMessages()
    while #logutil.messages > 0 do
        logutil.PopOldestMessage()
    end
end

function logutil.PatchFunctions(tab, name)
    -- Wrap each function in an error handler
    for key, value in pairs(tab) do
        if type(value) == "function" then
            local orig = value
            local funcName = ("%s.%s"):format(name, key)

            tab[key] = logutil.WrapFunctionInErrorHandler(orig, funcName)
        end
    end
end

function logutil.WrapFunctionInErrorHandler(func, funcName)
    funcName = funcName or "UnknownFunction"

    return function(...)
        local args = {...}
        local ret
        local success, err = pcall(function()
            ret = { func(unpack(args)) }
        end)

        if not success then
            Game_LogWarn_Original(0, ("Error in %q: %s"):format(funcName, tostring(err)))
            return nil
        end

        return unpack(ret)
    end
end

logutil.PatchFunctions(logutil, "logutil")
logutil.PatchFunctions(LogMessage, "LogMessage")

Game_LogWarn_Original(0, "Loaded logutil.lua")