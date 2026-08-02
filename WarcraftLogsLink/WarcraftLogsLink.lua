local MENU_TEXT = "WarcraftLogs Link"
local POPUP_NAME = "MLH_WCL_POPUP"

local REGION_BY_ID = {
    [1] = "us",
    [2] = "kr",
    [3] = "eu",
    [4] = "tw",
    [5] = "cn",
}

local function EncodeUrlPart(value)
    value = tostring(value or ""):lower():gsub("%s+", "-")
    value = value:gsub("[^%w%-_%.~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)

    return value
end

local function SplitNameAndRealm(fullName, fallbackUnit)
    if type(fullName) == "string" and fullName:find("|K", 1, true) then
        fullName = nil
    end

    local name, realm = strsplit("-", fullName or "", 2)

    if (not name or name == "") and fallbackUnit and UnitExists(fallbackUnit) then
        name, realm = UnitFullName(fallbackUnit)
    end

    if not realm or realm == "" then
        realm = GetRealmName()
    end

    return name, realm
end

local function BuildWarcraftLogsUrl(fullName, fallbackUnit)
    local name, realm = SplitNameAndRealm(fullName, fallbackUnit)

    if not name or name == "" or not realm or realm == "" then
        return "https://www.warcraftlogs.com/"
    end

    local region = REGION_BY_ID[GetCurrentRegion()] or "us"

    return string.format(
        "https://www.warcraftlogs.com/character/%s/%s/%s?zone=47",
        region,
        EncodeUrlPart(realm),
        EncodeUrlPart(name)
    )
end

local function HasCharacterNameAndRealm(fullName, fallbackUnit)
    local name, realm = SplitNameAndRealm(fullName, fallbackUnit)

    return name and name ~= "" and realm and realm ~= ""
end

local function GetPopupEditBox(popup)
    if not popup then
        return
    end

    if popup.editBox then
        return popup.editBox
    end

    if popup.GetEditBox then
        return popup:GetEditBox()
    end

    return _G[popup:GetName() .. "EditBox"]
end

local function ShowWarcraftLogsPopup(fullName, fallbackUnit)
    local popup = StaticPopup_Show(POPUP_NAME)
    local editBox = GetPopupEditBox(popup)

    if editBox then
        editBox:SetText(BuildWarcraftLogsUrl(fullName, fallbackUnit))
        editBox:HighlightText()
        editBox:SetFocus()
    end
end

---------------------------------------------------
-- Popup
---------------------------------------------------

StaticPopupDialogs[POPUP_NAME] = {
    text = MENU_TEXT,
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,

    EditBoxOnEscapePressed = function()
        StaticPopup_Hide(POPUP_NAME)
    end,

    OnShow = function(self)
        local editBox = GetPopupEditBox(self)

        if editBox then
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
}

---------------------------------------------------
-- LFG applicant context menu
---------------------------------------------------

local function GetApplicantPrimaryName(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)

        if type(value) == "number" and C_LFGList and C_LFGList.GetApplicantMemberInfo then
            local ok, name = pcall(C_LFGList.GetApplicantMemberInfo, value, 1)

            if ok and name then
                return name
            end
        elseif type(value) == "string" and value ~= "" then
            return value
        end
    end
end

local function AddApplicantButton(applicantName)
    if not HasCharacterNameAndRealm(applicantName) then
        return
    end

    local info = UIDropDownMenu_CreateInfo()
    info.text = MENU_TEXT
    info.notCheckable = true

    info.func = function()
        ShowWarcraftLogsPopup(applicantName)
    end

    UIDropDownMenu_AddButton(info)
end

---------------------------------------------------
-- Hook dropdown init
---------------------------------------------------

if LFGListUtil_OpenApplicantContextMenu then
    hooksecurefunc("LFGListUtil_OpenApplicantContextMenu", function(...)
        UIDropDownMenu_AddSeparator()
        AddApplicantButton(GetApplicantPrimaryName(...))
    end)
end

---------------------------------------------------
-- Player / target context menus
---------------------------------------------------

local UNIT_POPUP_VALUE = "MLH_WCL_LINK"

if UnitPopupButtons then
    UnitPopupButtons[UNIT_POPUP_VALUE] = {
        text = MENU_TEXT,
        dist = 0,
    }
end

local function AddUnitPopupMenuButton(menuName)
    local menu = UnitPopupMenus and UnitPopupMenus[menuName]

    if not menu then
        return
    end

    for _, value in ipairs(menu) do
        if value == UNIT_POPUP_VALUE then
            return
        end
    end

    local insertIndex = #menu

    for index, value in ipairs(menu) do
        if value == "CANCEL" then
            insertIndex = index
            break
        end
    end

    table.insert(menu, insertIndex, UNIT_POPUP_VALUE)
end

if UnitPopupButtons and UnitPopupMenus then
    AddUnitPopupMenuButton("SELF")
    AddUnitPopupMenuButton("PLAYER")
    AddUnitPopupMenuButton("ENEMY_PLAYER")
    AddUnitPopupMenuButton("FRIEND")
    AddUnitPopupMenuButton("GUILD")
    AddUnitPopupMenuButton("GUILD_OFFLINE")
    AddUnitPopupMenuButton("PARTY")
    AddUnitPopupMenuButton("RAID_PLAYER")
    AddUnitPopupMenuButton("TARGET")
end

if UnitPopup_OnClick then
    hooksecurefunc("UnitPopup_OnClick", function(self)
        if self.value ~= UNIT_POPUP_VALUE then
            return
        end

        local dropdown = UIDROPDOWNMENU_INIT_MENU
        local unit = dropdown and dropdown.unit
        local name = dropdown and dropdown.name
        local server = dropdown and dropdown.server

        if name and server and server ~= "" then
            name = name .. "-" .. server
        end

        ShowWarcraftLogsPopup(name, unit)
    end)
end

if TargetFrameDropDown_Initialize then
    hooksecurefunc("TargetFrameDropDown_Initialize", function()
        if not HasCharacterNameAndRealm(nil, "target") then
            return
        end

        UIDropDownMenu_AddSeparator()

        local info = UIDropDownMenu_CreateInfo()
        info.text = MENU_TEXT
        info.notCheckable = true
        info.func = function()
            ShowWarcraftLogsPopup(nil, "target")
        end

        UIDropDownMenu_AddButton(info, 1)
    end)
end

---------------------------------------------------
-- Modern Retail context menus
---------------------------------------------------

local modernMenusRegistered = false
local modernMenuRegistrationScheduled = false
local modernMenuManagerHooked = false

local function JoinNameRealm(name, realm)
    if type(name) == "string" and name:find("|K", 1, true) then
        return
    end

    if name and realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

local function GetTextValue(value)
    if type(value) == "string" and value ~= "" then
        if value:find("|K", 1, true) then
            return
        end

        return value
    end

    if type(value) == "table" and value.GetText then
        local text = value:GetText()

        if type(text) == "string" and text ~= "" then
            return text
        end
    end
end

local function GetCandidateNameFromTable(data)
    if type(data) ~= "table" then
        return
    end

    for _, key in ipairs({
        "name",
        "fullName",
        "fullname",
        "characterName",
        "playerName",
        "memberName",
    }) do
        local value = GetTextValue(data[key])

        if value then
            return value
        end
    end

    if data.memberInfo then
        return GetCandidateNameFromTable(data.memberInfo)
    end

    if data.member then
        return GetCandidateNameFromTable(data.member)
    end

    if data.elementData then
        return GetCandidateNameFromTable(data.elementData)
    end

    if data.data then
        return GetCandidateNameFromTable(data.data)
    end

    local nameText = GetTextValue(data.Name) or GetTextValue(data.nameText) or GetTextValue(data.NameText)

    if nameText then
        return nameText
    end
end

local function GetGuildNameFromOwner(owner)
    if not owner or not GetGuildRosterInfo then
        return
    end

    local guildIndex = owner.index or owner.guildIndex

    if not guildIndex and owner.GetParent then
        local parent = owner:GetParent()

        if parent then
            guildIndex = parent.index or parent.guildIndex

            if not guildIndex and parent.GetParent then
                local grandParent = parent:GetParent()

                if grandParent then
                    guildIndex = grandParent.index or grandParent.guildIndex
                end
            end
        end
    end

    if guildIndex then
        local name = GetGuildRosterInfo(guildIndex)

        if name then
            return name
        end
    end

    return GetCandidateNameFromTable(owner)
end

local function GetMenuTargetName(owner, contextData)
    if owner and owner.resultID and C_LFGList and C_LFGList.GetSearchResultInfo then
        local resultInfo = C_LFGList.GetSearchResultInfo(owner.resultID)

        if resultInfo then
            return resultInfo.leaderName
        end
    end

    if owner and owner.memberIdx and owner.GetParent and C_LFGList and C_LFGList.GetApplicantMemberInfo then
        local parent = owner:GetParent()
        local applicantID = parent and parent.applicantID

        if applicantID then
            local name = C_LFGList.GetApplicantMemberInfo(applicantID, owner.memberIdx)
            return name
        end
    end

    if contextData then
        if contextData.accountInfo and contextData.accountInfo.gameAccountInfo then
            local gameAccountInfo = contextData.accountInfo.gameAccountInfo

            return JoinNameRealm(gameAccountInfo.characterName, gameAccountInfo.realmName), contextData.unit
        end

        if contextData.friendsList and C_FriendList and C_FriendList.GetFriendInfoByIndex then
            local friendInfo = C_FriendList.GetFriendInfoByIndex(contextData.friendsList)

            if friendInfo and friendInfo.name then
                return friendInfo.name, contextData.unit
            end
        end

        if contextData.playerLocation then
            local guid = contextData.playerLocation.guid

            if not guid and contextData.playerLocation.GetGUID then
                guid = contextData.playerLocation:GetGUID()
            end

            if not guid and contextData.playerLocation.chatLineID and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
                guid = C_ChatInfo.GetChatLineSenderGUID(contextData.playerLocation.chatLineID)
            end

            if guid then
                local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
                return JoinNameRealm(name, realm), contextData.unit
            end
        end

        local fullName = JoinNameRealm(contextData.name, contextData.server)

        if fullName and fullName ~= "" then
            return fullName, contextData.unit
        end

        local guildName = GetGuildNameFromOwner(owner)

        if guildName then
            return guildName
        end

        local contextName = GetCandidateNameFromTable(contextData)

        if contextName then
            return contextName, contextData.unit
        end
    end

    local guildName = GetGuildNameFromOwner(owner)

    if guildName then
        return guildName
    end

    if GetGuildRosterSelection and GetGuildRosterInfo then
        local selectedIndex = GetGuildRosterSelection()

        if selectedIndex and selectedIndex > 0 then
            local selectedName = GetGuildRosterInfo(selectedIndex)

            if selectedName then
                return selectedName
            end
        end
    end

end

local function AddModernWarcraftLogsButton(owner, rootDescription, contextData)
    local fullName, unit = GetMenuTargetName(owner, contextData)

    if not HasCharacterNameAndRealm(fullName, unit) then
        return
    end

    rootDescription:CreateDivider()
    rootDescription:CreateButton(MENU_TEXT, function()
        ShowWarcraftLogsPopup(fullName, unit)
    end)
end

local function RegisterModernMenus()
    if modernMenusRegistered or not Menu or not Menu.ModifyMenu then
        return
    end

    modernMenusRegistered = true

    for _, tag in ipairs({
        "MENU_UNIT_ENEMY_PLAYER",
        "MENU_UNIT_GLUE_FRIEND",
        "MENU_UNIT_FRIEND",
        "MENU_UNIT_FRIEND_OFFLINE",
        "MENU_UNIT_BN_FRIEND",
        "MENU_UNIT_BN_FRIEND_OFFLINE",
        "MENU_UNIT_GUILD",
        "MENU_UNIT_GUILD_OFFLINE",
        "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
        "MENU_UNIT_PARTY",
        "MENU_UNIT_PLAYER",
        "MENU_UNIT_RAID_PLAYER",
        "MENU_UNIT_SELF",
        "MENU_UNIT_TARGET",
        "MENU_LFG_FRAME_MEMBER_APPLY",
        "MENU_LFG_FRAME_SEARCH_ENTRY",
    }) do
        Menu.ModifyMenu(tag, AddModernWarcraftLogsButton)
    end

end

local function RegisterModernMenusWhenReady()
    if Menu and Menu.ModifyMenu then
        RegisterModernMenus()
    end
end

local function ScheduleModernMenuRegistration(delay)
    if modernMenusRegistered or modernMenuRegistrationScheduled then
        return
    end

    modernMenuRegistrationScheduled = true

    local function Register()
        modernMenuRegistrationScheduled = false
        RegisterModernMenusWhenReady()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.1, Register)
    else
        Register()
    end
end

local function HookModernMenuManager()
    if modernMenuManagerHooked or not Menu or not Menu.GetManager then
        return
    end

    local manager = Menu.GetManager()

    if not manager then
        return
    end

    modernMenuManagerHooked = true

    if manager.OpenMenu then
        hooksecurefunc(manager, "OpenMenu", function()
            ScheduleModernMenuRegistration(1)
        end)
    end

    if manager.OpenContextMenu then
        hooksecurefunc(manager, "OpenContextMenu", function()
            ScheduleModernMenuRegistration(1)
        end)
    end
end

local function InitializeModernMenus()
    HookModernMenuManager()

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RaiderIO") then
        return
    else
        ScheduleModernMenuRegistration(1)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", InitializeModernMenus)
HookModernMenuManager()
