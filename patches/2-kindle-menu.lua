--[[
KOReader's main menu (TouchMenu) in the same style as the rest of the patches:

* tab bar: icon + short Portuguese name, active tab underlined
* light separators between items, "›" on items that open a submenu
* footer: "‹ Voltar" instead of the small up arrow

Only the look changes: the menu items themselves are KOReader's.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local TouchMenu = require("ui/widget/touchmenu")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen

local function S(px) return Screen:scaleBySize(px) end
local BLACK = Blitbuffer.COLOR_BLACK
local GRAY = Blitbuffer.COLOR_GRAY_5
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY

-- Open/close the menu without the black e-ink flash.
local NO_FLASH = true

local LABELS = {
    ["appbar.navigation"] = "Navegar",
    ["appbar.typeset"] = "Documento",
    ["appbar.settings"] = "Ajustes",
    ["appbar.tools"] = "Ferramentas",
    ["appbar.search"] = "Buscar",
    ["appbar.filebrowser"] = "Arquivos",
    ["appbar.menu"] = "Mais",
    ["plus"] = "Novo",
}

-- TouchMenuBar and TouchMenuItem are local to touchmenu.lua: reach them through upvalues.
local function upvalue(fn, name)
    for i = 1, 60 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
    end
end
local TouchMenuBar = upvalue(TouchMenu.init, "TouchMenuBar")
local TouchMenuItem = upvalue(TouchMenu.updateItems, "TouchMenuItem")
if not (TouchMenuBar and TouchMenuItem) then
    logger.warn("kindle-menu: TouchMenu internals not found, menu left unchanged")
    return
end

-------------------------------------------------------------------------------
-- Tab bar
-------------------------------------------------------------------------------

local TabCell = InputContainer:extend{ icon = nil, label = nil, width = 0, height = 0, active = false, callback = nil }

function TabCell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapTab = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    self:build()
end

function TabCell:build()
    local label = TextWidget:new{
        text = self.label or "", face = Font:getFace("cfont", 12),
        bold = self.active, fgcolor = self.active and BLACK or GRAY,
    }
    local isz = S(26)
    local under_w = math.min(self.width - S(8), math.max(label:getSize().w, isz) + S(14))
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height },
        VerticalGroup:new{ align = "center",
            IconWidget:new{ icon = self.icon, width = isz, height = isz },
            VerticalSpan:new{ width = S(4) },
            label,
            VerticalSpan:new{ width = S(6) },
            LineWidget:new{ dimen = Geom:new{ w = under_w, h = S(3) },
                background = self.active and BLACK or Blitbuffer.COLOR_WHITE },
        } }
end

function TabCell:setActive(active)
    if self.active ~= active then
        self.active = active
        self:build()
    end
end

function TabCell:onTapTab()
    if self.callback then self.callback() end
    return true
end
-- FocusManager compatibility (keys): behave like a button
function TabCell:onFocus() return true end
function TabCell:onUnfocus() return true end

TouchMenuBar.init = function(self)
    self.show_parent = self.show_parent or self
    local n = #self.icons
    local cw = math.floor(self.width / n)
    self.height = S(70)
    self.icon_widgets = {}
    local row = HorizontalGroup:new{}
    for k, icon in ipairs(self.icons) do
        local cell = TabCell:new{ icon = icon, label = LABELS[icon], width = cw, height = self.height }
        cell.callback = function()
            for i, c in ipairs(self.icon_widgets) do c:setActive(i == k) end
            self.menu:switchMenuTab(k)
        end
        table.insert(self.icon_widgets, cell)
        table.insert(self.menu.layout, cell)
        table.insert(row, cell)
    end
    self.bar_sep = LineWidget:new{ dimen = Geom:new{ w = self.width, h = math.max(1, S(1)) }, background = LIGHT }
    self[1] = VerticalGroup:new{ align = "left", row, self.bar_sep }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height + math.max(1, S(1)) }
end

-------------------------------------------------------------------------------
-- Items: "›" on submenus (the text is shortened so it never runs under it)
-------------------------------------------------------------------------------

local CHEVRON_W = S(34)
local orig_item_init = TouchMenuItem.init

-- KOReader appends " ▸" to submenu names; the "›" on the right replaces it.
local SUB_SUFFIX = " " .. require("ui/bidi").ltr("\u{25B8}")
local SUB_SUFFIX_LEN = #SUB_SUFFIX
for i = 1, 60 do
    local n, fn = debug.getupvalue(orig_item_init, i)
    if not n then break end
    if n == "getMenuText" then
        debug.setupvalue(orig_item_init, i, function(item)
            local t = fn(item)
            if type(t) == "string" and (item.sub_item_table or item.sub_item_table_func) then
                if t:sub(-SUB_SUFFIX_LEN) == SUB_SUFFIX then
                    t = t:sub(1, -SUB_SUFFIX_LEN - 1)
                else
                    t = t:gsub("%s*\u{25B8}$", "")
                end
            end
            return t
        end)
        break
    end
end
TouchMenuItem.init = function(self)
    local it = self.item
    local has_sub = it and (it.sub_item_table or it.sub_item_table_func)
    if not has_sub then return orig_item_init(self) end
    local full = self.dimen
    self.dimen = Geom:new{ x = full.x, y = full.y, w = full.w - CHEVRON_W, h = full.h }
    orig_item_init(self)
    self.dimen = full
    -- tap/hold ranges were built with the shorter width: give them the whole row
    self.ges_events.TapSelect[1].range = full
    self.ges_events.HoldSelect[1].range = full
    local dim = Geom:new{ w = full.w, h = full.h }
    self[1] = OverlapGroup:new{ dimen = dim:copy(),
        LeftContainer:new{ dimen = dim:copy(), self._underline_container },
        RightContainer:new{ dimen = dim:copy(), HorizontalGroup:new{ align = "center",
            TextWidget:new{ text = "›", face = Font:getFace("cfont", 22), fgcolor = GRAY },
            HorizontalSpan:new{ width = S(12) },
        } },
    }
end

-------------------------------------------------------------------------------
-- Separators and footer
-------------------------------------------------------------------------------

local function restyle(menu)
    -- light line between every item; section separators a bit darker
    local function line(color)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = S(10) },
            LineWidget:new{ background = color,
                dimen = Geom:new{ w = menu.item_width - 2 * S(10), h = menu.split_height } },
            HorizontalSpan:new{ width = S(10) },
        }
    end
    menu.split_span = line(Blitbuffer.COLOR_GRAY_E)
    menu.split_line = line(Blitbuffer.COLOR_GRAY_9)

    -- footer: "‹ Voltar" · page · clock/battery, same height as before
    local fh = menu.footer:getSize().h
    local third = math.floor((menu.width - menu.padding * 2) / 3)
    local back = InputContainer:new{
        CenterContainer:new{ dimen = Geom:new{ w = S(130), h = fh },
            TextWidget:new{ text = "‹  Voltar", face = Font:getFace("cfont", 16) } },
    }
    back.dimen = Geom:new{ x = 0, y = 0, w = S(130), h = fh }
    back.ges_events = { TapBack = { GestureRange:new{ ges = "tap", range = function() return back.dimen end } } }
    back.onTapBack = function() menu:backToUpperMenu() return true end
    menu.footer = HorizontalGroup:new{
        LeftContainer:new{ dimen = Geom:new{ w = third, h = fh }, back },
        CenterContainer:new{ dimen = Geom:new{ w = third, h = fh }, menu.page_info },
        RightContainer:new{ dimen = Geom:new{ w = third, h = fh }, menu.device_info },
    }
end

-- TouchMenu.init builds the items once (via switchToTab -> updateItems) after
-- creating the separators and footer. Swap them in right before that first
-- build, so the menu is only built once when it opens.
local orig_update = TouchMenu.updateItems
TouchMenu.updateItems = function(self, ...)
    if not self._kindle_styled then
        self._kindle_styled = true
        local ok, err = pcall(restyle, self)
        if not ok then logger.warn("kindle-menu:", err) end
        -- open without the black flash (see NO_FLASH)
        if NO_FLASH then self.is_fresh = false end
    end
    return orig_update(self, ...)
end

-------------------------------------------------------------------------------
-- No black flash
-------------------------------------------------------------------------------

-- KOReader flashes the screen black when the menu opens and flashes the whole
-- screen when it closes (against e-ink ghosting). Like the Kindle's own menus,
-- refresh only the menu's area without flashing.
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")

if NO_FLASH then
    TouchMenu.onCloseWidget = function(self)
        -- same guard as KOReader: nothing to refresh when FM/reader is going away
        local fm, rd = FileManager.instance, require("apps/reader/readerui").instance
        if (fm and not fm.tearing_down) or (rd and not rd.tearing_down) then
            UIManager:setDirty(nil, "ui", self.dimen and self.dimen:copy())
        end
    end
end

-------------------------------------------------------------------------------
-- Build the file browser's menu ahead of time
-------------------------------------------------------------------------------

-- KOReader only builds the menu lists on the first tap, and again every time
-- the file browser is recreated (after closing a book). Build them a moment
-- after it appears, so tapping "Menu" opens right away.
local orig_fm_init = FileManager.init
FileManager.init = function(self, ...)
    orig_fm_init(self, ...)
    UIManager:scheduleIn(2, function()
        local fmm = self.menu
        if FileManager.instance ~= self or self.tearing_down or not fmm or fmm.tab_item_table then return end
        local ok, err = pcall(fmm.setUpdateItemTable, fmm)
        if not ok then logger.warn("kindle-menu: prebuild", err) end
    end)
end
