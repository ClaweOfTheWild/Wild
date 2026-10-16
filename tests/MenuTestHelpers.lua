local MenuTestHelpers = {}

MenuTestHelpers.Response = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }

function MenuTestHelpers.NewDescription(kind, text, callback, data, isSelected, root)
    local description = {
        kind = kind, text = text, callback = callback, data = data,
        isSelected = isSelected, children = {},
    }
    description.root = root or description

    local function Add(self, childKind, childText, responder, childData, selected)
        local child = MenuTestHelpers.NewDescription(childKind, childText, responder,
            childData, selected, self.root)
        self.children[#self.children + 1] = child
        return child
    end

    function description:CreateButton(label, responder, value)
        return Add(self, "Button", label, responder, value)
    end
    function description:CreateRadio(label, selected, responder, value)
        local child = Add(self, "Radio", label, responder, value, selected)
        child.response = MenuTestHelpers.Response.CloseAll
        return child
    end
    function description:CreateCheckbox(label, selected, responder, value)
        local child = Add(self, "Checkbox", label, responder, value, selected)
        child.response = MenuTestHelpers.Response.Refresh
        return child
    end
    function description:CreateTitle(label) return Add(self, "Title", label) end
    function description:CreateDivider() return Add(self, "Divider") end
    function description:SetScrollMode(extent) self.scrollExtent = extent end
    function description:SetResponse(response) self.response = response end
    function description:IsSelected()
        return self.isSelected and self.isSelected(self.data) or false
    end
    function description:Pick()
        assert(self.callback, "Menu entry must have a responder")
        local response = self.callback(self.data) or self.response or MenuTestHelpers.Response.CloseAll
        if response == MenuTestHelpers.Response.CloseAll or response == MenuTestHelpers.Response.Close then
            self.root.open = false
        end
        return response
    end
    return description
end

function MenuTestHelpers.Install(env, methods, state)
    env.MenuResponse = MenuTestHelpers.Response
    function methods:OverrideText(text) self.text = text end
    function methods:SetupMenu(generator)
        self.menuGenerator = generator
        if self:IsShown() then self:GenerateMenu() end
    end
    function methods:GenerateMenu()
        local root = MenuTestHelpers.NewDescription("Root")
        self.menuGenerator(self, root)
        self.menuDescription = root
        return root
    end
    env.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            assert(owner:IsVisible(), "Context menus need a visible owner")
            local root = MenuTestHelpers.NewDescription("Root")
            root.open = true
            generator(owner, root)
            state.contextMenu, state.contextOwner = root, owner
            return root
        end,
    }

    local createFrame = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        assert(not template or not template:find("UIDropDown", 1, true),
            "Legacy dropdown frames share Blizzard's tainted menu state")
        return createFrame(kind, name, parent, template)
    end
    local function RejectLegacyMenu()
        error("Wild settings must not use Blizzard's shared legacy dropdown API")
    end
    for _, name in ipairs({
        "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton",
        "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth", "ToggleDropDownMenu", "CloseDropDownMenus",
    }) do
        env[name] = RejectLegacyMenu
    end
end

return MenuTestHelpers
