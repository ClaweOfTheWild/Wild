-- Wild: Player-triggered keyboard confirmation for standard popups
local ADDON_NAME, Wild = ...

local DELETE_POPUPS = {
    DELETE_ITEM = true,
    DELETE_QUEST_ITEM = true,
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}
local EXCLUDED_POPUPS = {
    ADDON_ACTION_FORBIDDEN = true,
    ADDON_ACTION_BLOCKED = true,
    TOO_MANY_LUA_ERRORS = true,
}
local MODIFIER_KEYS = {
    LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LSHIFT = true, RSHIFT = true,
}
local NAMED_KEYS = {
    SPACE = true, ENTER = true, TAB = true, BACKSPACE = true,
    INSERT = true, DELETE = true, HOME = true, END = true,
    PAGEUP = true, PAGEDOWN = true, UP = true, DOWN = true,
    LEFT = true, RIGHT = true, NUMLOCK = true, CAPSLOCK = true,
    SCROLLLOCK = true, PAUSE = true, PRINTSCREEN = true,
    NUMPADPLUS = true, NUMPADMINUS = true, NUMPADMULTIPLY = true,
    NUMPADDIVIDE = true, NUMPADDECIMAL = true, NUMPADENTER = true,
}

local receiver = CreateFrame("Frame", nil, UIParent)
receiver:SetFrameStrata("TOOLTIP")
receiver:EnableKeyboard(true)
receiver:SetPropagateKeyboardInput(true)
receiver:Hide()
local bindingOwner = CreateFrame("Frame")
local bindingActive = false
local bindingTimeout
local hookedPopups, hookedButtons = {}, {}

local function GetConfig()
    return Wild.db and Wild.db.dialogKey
end

local function Warn(message)
    print("|cffff6600Wild:|r " .. message)
end

local function ClearBinding()
    if bindingTimeout then
        bindingTimeout:Cancel()
        bindingTimeout = nil
    end
    if bindingActive and not InCombatLockdown() then
        ClearOverrideBindings(bindingOwner)
        bindingActive = false
    end
end

local function NormalizeKey(value)
    if type(value) ~= "string" then return nil end
    local key = strtrim(value):upper()
    local modifiers = {}
    while true do
        local modifier, rest = key:match("^(%u+)%-(.+)$")
        if modifier ~= "CTRL" and modifier ~= "ALT" and modifier ~= "SHIFT" then break end
        if modifiers[modifier] then return nil end
        modifiers[modifier], key = true, rest
    end
    local number = tonumber(key:match("^F(%d+)$"))
    local valid = NAMED_KEYS[key] or key:match("^[A-Z0-9]$") or
        key:match("^NUMPAD[0-9]$") or
        (#key == 1 and ("`-=[]\\;',./"):find(key, 1, true)) or
        (number and number >= 1 and number <= 24 and key == "F" .. number)
    if not valid then return nil end
    return (modifiers.CTRL and "CTRL-" or "") ..
        (modifiers.ALT and "ALT-" or "") ..
        (modifiers.SHIFT and "SHIFT-" or "") .. key
end

function Wild.SetDialogKey(key)
    local normalized = NormalizeKey(key)
    if not normalized then
        Warn("Invalid dialog key. Use a keyboard key such as SPACE or CTRL-F2; Escape is reserved for cancel.")
        return false
    end
    if not GetConfig() then
        Warn("Dialog key settings are unavailable.")
        return false
    end
    Wild.db.dialogKey.key = normalized
    ClearBinding()
    return true
end

function Wild.UpdateDialogKey()
    ClearBinding()
    local cfg = GetConfig()
    if cfg and cfg.enabled and not InCombatLockdown() then
        receiver:Show()
    else
        receiver:Hide()
    end
end

local function GetFrontPopup()
    local front, forbidden
    local function Consider(popup)
        if popup:IsForbidden() then forbidden = true; return end
        if not popup:IsVisible() then return end
        if not front or (popup:GetTop() or 0) > (front:GetTop() or 0) then
            front = popup
        end
    end
    if StaticPopup_ForEachShownDialog then
        StaticPopup_ForEachShownDialog(Consider)
    else
        for index = 1, 4 do
            local popup = _G["StaticPopup" .. index]
            if popup then Consider(popup) end
        end
    end
    if not forbidden then return front end
end

local function GetTarget()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled or InCombatLockdown() then return nil end
    if WildSettingsFrame and WildSettingsFrame:IsShown() then return nil end
    local popup = GetFrontPopup()
    if not popup or popup:IsForbidden() or popup.special then return nil end
    local info = popup.dialogInfo or StaticPopupDialogs[popup.which]
    if not info or info.ignoreKeys or info.editBoxSecureText or EXCLUDED_POPUPS[popup.which] then return nil end
    local destroy = DELETE_POPUPS[popup.which]
    if destroy and (not cfg.destroy or not CursorHasItem()) then return nil end
    local editBox = popup.GetEditBox and popup:GetEditBox() or popup.editBox
    if editBox and editBox:IsForbidden() then return nil end
    if info.hasEditBox and not destroy then return nil end
    local focus = GetCurrentKeyBoardFocus()
    if focus and not (destroy and focus == editBox) then return nil end
    local button = popup.GetButton1 and popup:GetButton1() or popup.button1
    if not button or button:IsForbidden() or not button:IsVisible() then return nil end
    if popup.startDelay or popup.acceptDelay then return nil end
    if not button:IsEnabled() and not (destroy and info.hasEditBox) then return nil end
    return popup, button, info.hasEditBox and editBox or nil
end

local function PrepareConfirmation(popup, button, editBox)
    if editBox then
        -- Only the four cursor-item delete dialogs may bypass typed confirmation.
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
        if not button:IsEnabled() then return false end
        editBox:ClearFocus()
    end
    return button:IsEnabled() and popup:IsVisible()
end

-- Must be called from a hardware event (for example, a macro or a button click).
function Wild.ConfirmDialog()
    local popup, button, editBox = GetTarget()
    if not popup or not PrepareConfirmation(popup, button, editBox) then return false end
    button:Click("LeftButton")
    return true
end

receiver:SetScript("OnKeyDown", function(_, key)
    if InCombatLockdown() then return end
    ClearBinding()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled or MODIFIER_KEYS[key] then return end
    local pressed = (IsControlKeyDown() and "CTRL-" or "") ..
        (IsAltKeyDown() and "ALT-" or "") ..
        (IsShiftKeyDown() and "SHIFT-" or "") .. key
    if pressed ~= cfg.key then return end
    local popup, button, editBox = GetTarget()
    if not popup then return end
    local name = button:GetName()
    if not name then
        Warn("This popup has no named confirmation button; click it manually.")
        return
    end
    if not PrepareConfirmation(popup, button, editBox) then return end
    if not hookedPopups[popup] then
        popup:HookScript("OnHide", ClearBinding)
        hookedPopups[popup] = true
    end
    if not hookedButtons[button] then
        button:HookScript("OnClick", ClearBinding)
        hookedButtons[button] = true
    end
    -- Let WoW dispatch the physical key to its own button, including protected actions.
    SetOverrideBindingClick(bindingOwner, true, pressed, name, "LeftButton")
    bindingActive = true
    -- Safety only: clear if the key is never released or the button does not dispatch.
    bindingTimeout = C_Timer.NewTimer(5, ClearBinding)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= ADDON_NAME then return end
    Wild.UpdateDialogKey()
end)
