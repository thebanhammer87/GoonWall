--[[ -----------------------------------------------------------------------

UI Handlers

--]] -----------------------------------------------------------------------

function GoonWallInterfaceFrame_LoadOptions(self, mode)
    goonwall.Debug(GOON_LOG_INFO, 'Loading interface settings (mode=%s)', tostring(mode))

    -- Populate interface panel.
    if not mode then
        mode = goonwall.settings:mode()
    end
    getglobal(self:GetName() .. "OptionMode"):SetChecked(mode == GOON_MODE_ACCOUNT)
    getglobal(self:GetName() .. "OptionTag"):SetChecked(goonwall.settings:get('tag', mode))
    getglobal(self:GetName() .. "OptionRoster"):SetChecked(goonwall.settings:get('roster', mode))
    getglobal(self:GetName() .. "OptionJoinDelay"):SetValue(goonwall.settings:get('joindelay', mode))
end

function GoonWallInterfaceFrame_OnShow(self)
    if (not goonwall.addon_loaded) then
        -- Configuration not loaded.
        self:Hide()
        return
    end
    goonwall.Debug(GOON_LOG_INFO, 'Displaying interface options')

    -- Initialize widgets
    getglobal(self:GetName() .. "OptionJoinDelay"):SetMinMaxValues(goonwall.settings:getattr('joindelay', 'min'),
        goonwall.settings:getattr('joindelay', 'max'))
    getglobal(self:GetName() .. "OptionJoinDelay"):SetValueStep(goonwall.settings:getattr('joindelay', 'step'))

    -- Display configured values
    GoonWallInterfaceFrame_LoadOptions(self)
end

function GoonWallInterfaceFrame_SaveUpdates(self)
    goonwall.Debug(GOON_LOG_INFO, 'Saving interface settings')
    local mode = getglobal(self:GetName() .. "OptionMode"):GetChecked() and GOON_MODE_ACCOUNT or GOON_MODE_CHARACTER
    goonwall.settings:set('mode', mode)
    goonwall.settings:set('tag', getglobal(self:GetName() .. "OptionTag"):GetChecked() and true or false, mode)
    goonwall.settings:set('roster', getglobal(self:GetName() .. "OptionRoster"):GetChecked() and true or false, mode)
    goonwall.settings:set('joindelay', getglobal(self:GetName() .. "OptionJoinDelay"):GetValue(), mode)
end

function GoonWallInterfaceFrame_SetDefaults(self)
    goonwall.Debug(GOON_LOG_INFO, 'Resetting interface settings')
    goonwall.settings:reset()
end

function GoonWallInterfaceFrameOptionMode_OnClick(self)
    local mode = self:GetChecked() and GOON_MODE_ACCOUNT or GOON_MODE_CHARACTER
    goonwall.Debug(GOON_LOG_DEBUG, 'Mode toggled: %s', mode)
    GoonWallInterfaceFrame_LoadOptions(self:GetParent(), mode)
end

function GoonWallInterfaceFrameOptionJoinDelay_OnValueChanged(self, value)
    -- Fix for 5.4.0, see http://www.wowwiki.com/Patch_5.4.0/API_changes
    goonwall.Debug(GOON_LOG_DEBUG, 'Join delay setting updated')
    if not self._onsetting then
        self._onsetting = true
        self:SetValue(self:GetValue())
        value = self:GetValue()
        self._onsetting = false
    else return
    end
    getglobal(self:GetName() .. "Text"):SetText(value)
end
