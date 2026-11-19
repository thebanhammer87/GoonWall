--[[ -----------------------------------------------------------------------

Imported Libraries

--]] -----------------------------------------------------------------------

local semver = LibStub:GetLibrary("SemanticVersion-1.0")


--
-- Kludge to avoid the MoP glyph bug
--
local _


--[[ -----------------------------------------------------------------------

Slash Command Handler

--]] -----------------------------------------------------------------------

--- Update or display the value of a user settings variable.
-- @param key The name of the variable.
-- @param value The variable value.
local function GoonSettingCmd(key, value)
    if goonwall.settings:getattr(key, 'type') == 'boolean' then
        if value and value ~= '' then
            if value == 'on' then
                goonwall.settings:set(key, true)
            elseif value == 'off' then
                goonwall.settings:set(key, false)
            else
                goonwall.Error('%s setting must be "on" or "off"', key)
            end
        end
        goonwall.Write('%s is turned %s.',
                goonwall.settings:getattr(key, 'desc'),
                goonwall.settings:get(key) and 'ON' or 'OFF'
        )
    elseif goonwall.settings:getattr(key, 'type') == 'number' then
        if value and value ~= '' then
            if value:match('^-?%d+$') then
                goonwall.settings:set(key, value + 0)
            else
                goonwall.Error('%s setting must be numeric', key)
            end
        end
        goonwall.Write('%s is set to %s.',
                goonwall.settings:getattr(key, 'desc'),
                tostring(goonwall.settings:get(key))
        )
    elseif goonwall.settings:getattr(key, 'type') == 'string' then
        if value and value ~= '' then
            goonwall.settings:set(key, value)
        end
        goonwall.Write('%s is set to %s.',
                goonwall.settings:getattr(key, 'desc'),
                goonwall.settings:get(key)
        )
    else
        goonwall.Error('cannot parse value for %s', key)
    end

end

local function GoonSlashCmd(message, editbox)

    --
    -- Parse the command
    --
    local command, argstr = message:match('^(%S*)%s*(%S*)%s*')
    command = command:lower()

    goonwall.Debug(GOON_LOG_NOTICE, 'command=%s, args=%s', command, argstr)

    if command == nil or command == '' or command == 'help' then

        for line in string.gmatch(goonwall.usage, '([^\n]*)\n') do
            goonwall.Write(line)
        end

    elseif goonwall.settings:exists(command) then

        GoonSettingCmd(command, argstr)

    elseif command == 'reload' or command == 'refresh' then

        goonwall.Write('Reloading configuration.')
        goonwall.config:reload()

    elseif command == 'reset' then

        goonwall.Write('Resetting configuration.')
        goonwall.config:reset()

    elseif command == 'dump' then

        goonwall.config:dump()

    elseif command == 'status' then

        goonwall.config:dump_status()

    elseif command == 'version' then

        goonwall.Write('GoonWall version %s.', goonwall.version)
        goonwall.Write('World of Warcraft version %s, build %s (%s), interface %s.',
                goonwall.build['version'], goonwall.build['number'], goonwall.build['date'], goonwall.build['interface'])
        goonwall.Write('Interpreter version %s', _VERSION)

    else

        goonwall.Error('Unknown command: %s', command)

    end
end


--[[ -----------------------------------------------------------------------

Initialization

--]] -----------------------------------------------------------------------
function GoonWall_OnLoad(self)

    --
    -- Set up slash commands
    --
    SLASH_GOONWALL1 = '/goonwall'
    SLASH_GOONWALL2 = '/gw'
    SlashCmdList['GOONWALL'] = GoonSlashCmd

    --
    -- Trap the events we are interested in
    --
    self:RegisterEvent('ADDON_LOADED')
    self:RegisterEvent('CHANNEL_UI_UPDATE')
    self:RegisterEvent('CHAT_MSG_CHANNEL')
    self:RegisterEvent('CHAT_MSG_CHANNEL_JOIN')
    self:RegisterEvent('CHAT_MSG_CHANNEL_LEAVE')
    self:RegisterEvent('CHAT_MSG_CHANNEL_NOTICE')
    self:RegisterEvent('CHAT_MSG_GUILD')
    self:RegisterEvent('CHAT_MSG_SYSTEM')
    self:RegisterEvent('GUILD_ROSTER_UPDATE')
    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    self:RegisterEvent('PLAYER_GUILD_UPDATE')
    self:RegisterEvent('PLAYER_LOGIN')
    -- Optional: flush held sends after lockdown; pcall since unknown events raise.
    for _, event in ipairs({ 'PLAYER_REGEN_ENABLED', 'ENCOUNTER_END', 'CHALLENGE_MODE_COMPLETED', 'ZONE_CHANGED_NEW_AREA' }) do
        pcall(self.RegisterEvent, self, event)
    end

    --
    -- Add a tab to the Interface Options panel.
    --
    self.name = 'GoonWall'
    self.refresh = function(self)
        GoonWallInterfaceFrame_OnShow(self)
    end
    self.okay = function(self)
        GoonWallInterfaceFrame_SaveUpdates(self)
    end
    self.cancel = function(self)
        return
    end
    self.default = function(self)
        GoonWallInterfaceFrame_SetDefaults(self)
    end

    local category = Settings.RegisterCanvasLayoutCategory(self, self.name)
    Settings.RegisterAddOnCategory(category)

    -- Settings.RegisterCanvasLayoutCategory (unlike the removed
    -- InterfaceOptions_AddCategory it replaced) never calls self.okay,
    -- self.cancel, or self.refresh - those belonged to the old panel
    -- container's Okay/Cancel button flow. None of this panel's controls
    -- have their own save-on-change handler, so every checkbox/slider here
    -- visually toggles but GoonWallInterfaceFrame_SaveUpdates is never
    -- invoked, meaning changes are silently discarded. Save immediately on
    -- interaction instead, matching how the new Settings API expects
    -- panels to behave.
    local function GoonSaveOnChange()
        GoonWallInterfaceFrame_SaveUpdates(GoonWallInterfaceFrame)
    end
    GoonWallInterfaceFrameOptionMode:HookScript('OnClick', GoonSaveOnChange)
    GoonWallInterfaceFrameOptionTag:HookScript('OnClick', GoonSaveOnChange)
    GoonWallInterfaceFrameOptionRoster:HookScript('OnClick', GoonSaveOnChange)
    GoonWallInterfaceFrameOptionJoinDelay:HookScript('OnValueChanged', GoonSaveOnChange)
end


--[[ -----------------------------------------------------------------------

Hooks

--]] -----------------------------------------------------------------------
local pendingEditBoxSend

local function GoonWall_ForwardChatMessage(chatType, message)
    if goonwall.compatibility.name2chat then
        message = string.format('(%s) %s', Name2Chat.db.profile.name, message)
    end
    if goonwall.compatibility.identity then
        message = Identity2:AlterMessage(message, Identity2.db.profile.channels[chatType])
    end
    if (chatType == 'GUILD') then
        if goonwall.compatibility.incognito then
            if Incognito.db.profile.enable and
                    Incognito.db.profile.name and
                    Incognito.db.profile.name ~= "" and
                    Incognito.db.profile.guild then
                message = "(" .. Incognito.db.profile.name .. "): " .. message
            end
        end
        goonwall.config.channel.guild:send(GOON_MTYPE_CHAT, message)
    end
end

function GoonWall_ParseText(chat, send)
    if (send == 1) then
        local chatType = chat:GetAttribute('chatType')
        local message = chat:GetText()
        goonwall.Debug(GOON_LOG_DEBUG, 'type=%s, message=%q', chatType, message)
        if goonwall.IsUsableString(message) and message:match('%S') then
            if chatType == 'GUILD' then
                -- The actual SendChatMessage call follows this edit-box hook.
                -- Remember it so the API hook below does not relay typed messages
                -- twice. Macros bypass this callback and are handled by that hook.
                pendingEditBoxSend = {
                    chatType = chatType,
                    message = message,
                    time = GetTime(),
                }
                GoonWall_ForwardChatMessage(chatType, message)
            end
        end
    end
end

function GoonWall_SendChatMessage(message, chatType)
    if goonwall.IsSecret(chatType) or goonwall.IsSecret(message) or chatType ~= 'GUILD' then
        return
    end

    local pending = pendingEditBoxSend
    pendingEditBoxSend = nil
    if pending and pending.chatType == chatType and pending.message == message and
            GetTime() - pending.time <= 1 then
        return
    end

    goonwall.Debug(GOON_LOG_DEBUG, 'captured direct send; type=%s, message=%q', chatType, message)
    if goonwall.IsUsableString(message) and message:match('%S') then
        -- This function runs as a secure post-hook of SendChatMessage. Sending
        -- the GoonWall channel copy from inside that protected call stack can
        -- trigger ADDON_ACTION_BLOCKED when another addon originated the guild
        -- message. Defer only the captured direct-send path to the next frame;
        -- typed edit-box messages continue to use GoonWall_ParseText above.
        C_Timer.After(0, function()
            GoonWall_ForwardChatMessage(chatType, message)
        end)
    end
end

--
-- Patch 1.15.9 (and Retail 11.0) refactored the chat edit box into a mixin.
-- The global ChatEdit_ParseText became a dead deprecation alias, and the client
-- now calls the edit box's own ParseText method -- so hooking the global no
-- longer fires and outbound bridging silently stops. Where the mixin method
-- exists, hook each chat edit box instance's ParseText directly; otherwise fall
-- back to the legacy global hook for older clients.
--
goonwall.hooks = { editbox = 0, parsetext = false, sendchat = false }

if ChatFrame1EditBox and type(ChatFrame1EditBox.ParseText) == 'function' then
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local editbox = _G['ChatFrame' .. i .. 'EditBox']
        if editbox and type(editbox.ParseText) == 'function' then
            hooksecurefunc(editbox, 'ParseText', GoonWall_ParseText)
            goonwall.hooks.editbox = goonwall.hooks.editbox + 1
        end
    end
    goonwall.hooks.parsetext = goonwall.hooks.editbox > 0
elseif type(ChatEdit_ParseText) == 'function' then
    hooksecurefunc('ChatEdit_ParseText', GoonWall_ParseText)
    goonwall.hooks.parsetext = true
end

-- Macro and addon-originated guild messages call SendChatMessage directly and
-- never pass through the chat edit box hooks above.
if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == 'function' then
    hooksecurefunc(C_ChatInfo, 'SendChatMessage', GoonWall_SendChatMessage)
    goonwall.hooks.sendchat = true
elseif type(SendChatMessage) == 'function' then
    hooksecurefunc('SendChatMessage', GoonWall_SendChatMessage)
    goonwall.hooks.sendchat = true
end

--[[ -----------------------------------------------------------------------

Restricted Chat Handling

--]] -----------------------------------------------------------------------

local function in_guild()
    if type(IsInGuild) ~= 'function' then
        return false
    end
    local ok, rv = pcall(IsInGuild)
    return not ok or goonwall.IsSecret(rv) or rv == true
end

--- Reset the configuration if guild membership or rank changed.
-- Deferred in battlegrounds and while the status is unreadable.
function goonwall.CheckGuildStatus()
    local new_status = goonwall.GetGuildStatus()
    local member = in_guild()
    local restricted = goonwall.InRestrictedInstance()
    goonwall.Debug(GOON_LOG_DEBUG, 'guild status; was=%s, now=%s, in_guild=%s, restricted=%s',
            tostring(goonwall.guild_status), tostring(new_status), tostring(member), tostring(restricted))
    if restricted or new_status == nil or (new_status == '' and member) then
        goonwall.guild_check_pending = true
        return false
    end
    goonwall.guild_check_pending = false
    if goonwall.guild_status ~= new_status then
        goonwall.config:reset()
        goonwall.guild_status = new_status
        return true
    end
    return false
end

--- Coalesce bursts of CHANNEL_UI_UPDATE into one channel refresh.
function goonwall.QueueChannelRefresh()
    local function refresh()
        goonwall.refresh_queued = false
        if goonwall.GetGuildName() ~= nil then
            goonwall.config:refresh_channels()
        end
    end
    if not (C_Timer and type(C_Timer.After) == 'function') then
        return refresh()
    end
    if not goonwall.refresh_queued then
        goonwall.refresh_queued = true
        C_Timer.After(GOON_CHANNEL_REFRESH_DELAY, refresh)
    end
end

--- Catch up on work held back during combat, lockdown or battlegrounds.
function goonwall.OnRestrictionChange(event)
    local lockdown, combat, instance = goonwall.RestrictionState()
    goonwall.Debug(GOON_LOG_DEBUG, 'restriction check; event=%s, lockdown=%s, combat=%s, instance=%s',
            tostring(event), tostring(lockdown), tostring(combat), tostring(instance))
    goonwall.ReportSuppressedDebug()
    if not goonwall.InRestrictedInstance() then
        if goonwall.guild_check_pending then
            goonwall.CheckGuildStatus()
        end
        for _, channel in pairs(goonwall.config.channel) do
            if channel.join_pending then
                goonwall.QueueChannelRefresh()
            end
        end
    end
    for _, channel in pairs(goonwall.config.channel) do
        channel:tl_flush()
    end
end

--[[ -----------------------------------------------------------------------

Frame Event Functions

--]] -----------------------------------------------------------------------
function GoonWall_OnEvent(self, event, ...)

    goonwall.Debug(GOON_LOG_DEBUG, 'event occurred; event=%s', event)

    --
    -- Addon loading check
    --
    if event == 'ADDON_LOADED' and select(1, ...) == 'GoonWall' then

        --
        -- Initialize the saved variables
        --
        goonwall.settings = GoonSettings:new()

        --
        -- Initialize the confederation configuration
        --
        goonwall.config = GoonConfig:new()

        --
        -- Thundercats are go!
        --
        goonwall.addon_loaded = true
        goonwall.RefreshPlayerIdentity()
        goonwall.Write('v%s loaded.', goonwall.version)
        if not goonwall.hooks.parsetext then
            goonwall.Error('No chat edit box hook point found; typed guild chat will not be bridged.')
        end
        if not goonwall.hooks.sendchat then
            goonwall.Error('No SendChatMessage hook point found; macro guild chat will not be bridged.')
        end
        goonwall.Debug(GOON_LOG_DEBUG, 'loading complete; name=%s, realm=%s', tostring(goonwall.player), tostring(goonwall.realm))
    end

    if not goonwall.addon_loaded then
        return -- early exit
    end

    --
    -- Main event switch
    --
    if event == 'CHAT_MSG_CHANNEL' then

        local chanNum = select(8, ...)

        if goonwall.IsSecret(chanNum) then
            goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, secret channel number; ignored', event)
        elseif chanNum == goonwall.config.channel.guild.number then
            goonwall.config.channel.guild:receive(goonwall.handlerGuildChat, ...)
        end

    elseif event == 'CHAT_MSG_GUILD' then

        -- Messages will be forwarded by the ChatEdit_ParseText hook
        local message, sender, language, _, _, flags, _, chanNum = select(1, ...)
        goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, sender=%s, message=%q', event, sender, message)

    elseif event == 'CHAT_MSG_CHANNEL_JOIN' then

        local _, player, _, _, _, _, _, number = select(1, ...)

        if goonwall.IsSecret(number) or goonwall.IsSecret(player) then
            goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, secret arguments; ignored', event)
        elseif number == goonwall.config.channel.guild.number then
            if GetCVar('guildMemberNotify') == '1' and goonwall.settings:get('roster') then
                local key = goonwall.NormalizeName(player)
                if not key then
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: unusable player name')
                elseif goonwall.config.comember_cache:hold(key) then
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: hit %s', key)
                else
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: miss %s', key)
                    goonwall.ReplicateMessage('SYSTEM', format(ERR_FRIEND_ONLINE_SS, player, player))
                end
            end
        end

    elseif event == 'CHAT_MSG_CHANNEL_LEAVE' then

        local _, player, _, _, _, _, _, number = select(1, ...)

        if goonwall.IsSecret(number) or goonwall.IsSecret(player) then
            goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, secret arguments; ignored', event)
        elseif number == goonwall.config.channel.guild.number then
            if GetCVar('guildMemberNotify') == '1' and goonwall.settings:get('roster') then
                local key = goonwall.NormalizeName(player)
                if not key then
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: unusable player name')
                elseif goonwall.config.comember_cache:hold(key) then
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: hit %s', key)
                else
                    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: miss %s', key)
                    goonwall.ReplicateMessage('SYSTEM', format(ERR_FRIEND_OFFLINE_S, player))
                end
            end
        end

    elseif event == 'CHANNEL_UI_UPDATE' then

        goonwall.QueueChannelRefresh()

        if goonwall.config.timer.channel:hold() then
            for _, v in ipairs({ GetChannelList() }) do
                if v == 'General' then
                    goonwall.config.timer.channel:clear()
                end
            end
        end

    elseif event == 'CHAT_MSG_CHANNEL_NOTICE' then

        local action, _, _, _, _, _, type, number, name = select(1, ...)

        if goonwall.IsSecret(action) or goonwall.IsSecret(type) or goonwall.IsSecret(number) then
            goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, secret arguments; ignored', event)
        elseif number == goonwall.config.channel.guild.number then

            if action == 'YOU_LEFT' then
                goonwall.config.channel.guild.stats.disco = goonwall.config.channel.guild.stats.disco + 1
                goonwall.config:refresh_channels()
            end

        elseif type == 1 then

            if action == 'YOU_JOINED' or action == 'YOU_CHANGED' then
                goonwall.Debug(GOON_LOG_NOTICE, 'world channel joined, unblocking reconnect.')
                goonwall.config.timer.channel:clear()
                goonwall.config:refresh_channels()
            end
        end

    elseif event == 'CHAT_MSG_SYSTEM' then

        local message = select(1, ...)
        goonwall.Debug(GOON_LOG_DEBUG, 'event=%s, message=%q', event, message)
        local handler = GoonSystemEventHandler:factory(goonwall.config, message)
        handler:run()

    elseif event == 'GUILD_ROSTER_UPDATE' then

        goonwall.ScanRosterForPlayer()

        if goonwall.config:load() then
            goonwall.config:refresh_channels()
        end

    elseif event == 'PLAYER_ENTERING_WORLD' then

        C_ChatInfo.RegisterAddonMessagePrefix("GoonWall")
        -- Apply compatibility workarounds
        goonwall.EnableCompatibility()
        goonwall.OnRestrictionChange(event)

    elseif event == 'PLAYER_GUILD_UPDATE' then

        goonwall.CheckGuildStatus()

    elseif event == 'PLAYER_REGEN_ENABLED' or event == 'ENCOUNTER_END' or event == 'CHALLENGE_MODE_COMPLETED' or
            event == 'ZONE_CHANGED_NEW_AREA' then

        goonwall.OnRestrictionChange(event)

    elseif event == 'PLAYER_LOGIN' then

        goonwall.RefreshPlayerIdentity()

        -- Defer joining to allow General to grab slot 1
        goonwall.config.timer.channel:start(function()
            goonwall.config:refresh_channels()
        end)

        -- Initiate the comms
        goonwall.config:refresh()
    end
end


--[[ -----------------------------------------------------------------------

END

--]] -----------------------------------------------------------------------
