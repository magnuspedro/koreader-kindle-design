--[[
Kindle-style reading UI for EPUB/CRE books (PDFs keep KOReader's own UI).

* Tap the top of the page  -> toolbar: Biblioteca · Índice · Aa · Buscar · Marcar · Menu
* Tap the bottom of the page, long-press the top bar, or "Aa" -> "Aa" panel
  with tabs Temas · Fonte · Layout · Mais. Changes apply right away and also
  become the default for books opened for the first time (like the Kindle).
* "Índice" -> simple full-screen table of contents.
* "Menu" and "Mais > Todas as opções" still reach every KOReader setting.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderMenu = require("apps/reader/modules/readermenu")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local Screen = Device.screen

local function S(px) return Screen:scaleBySize(px) end

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY = Blitbuffer.COLOR_GRAY_5    -- secondary text
local MID = Blitbuffer.COLOR_GRAY_9     -- unselected borders, slider track
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY -- dividers

-- Values offered by the panel
local SIZES = { 14, 16, 18, 20, 21, 22, 24, 26, 28, 30, 34, 38, 44 }
local WEIGHTS = { -1, -0.5, 0, 0.5, 1, 1.5 }
local GAMMAS = { 15, 25, 30, 36, 43, 49 }
local LINE_SPACINGS = { 100, 110, 125 }
local MARGINS = { 15, 30, 50 }
local RENDER_MODES = { { 2, "Livro" }, { 3, "Web" }, { 1, "Plano" } }
local WORD_SPACINGS = {
    { G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_SMALL"), "Pequeno" },
    { G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_MEDIUM"), "Médio" },
    { G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_LARGE"), "Grande" },
}
local THEMES = {
    { name = "Compacto", font_size = 18, line_spacing = 100, margin = 15, weight = -0.5 },
    { name = "Padrão",   font_size = 21, line_spacing = 110, margin = 30, weight = -0.5 },
    { name = "Grande",   font_size = 26, line_spacing = 115, margin = 30, weight = 0 },
}
-- Fonts not meant for reading Latin text are hidden from the font list.
local HIDDEN_FONTS = { "CJK", "Arabic", "Naskh", "Hebrew", "Devanagari", "Bengali", "Thai",
    "Symbol", "Emoji", "Math", "Nerd", "Mono", "Sans Sinhala", "Tamil", "Khmer", "Myanmar" }

-------------------------------------------------------------------------------
-- Small building blocks
-------------------------------------------------------------------------------

local function text(str, size, opts)
    opts = opts or {}
    return TextWidget:new{
        text = str,
        face = opts.face or Font:getFace("cfont", size),
        bold = opts.bold,
        fgcolor = opts.color or BLACK,
        max_width = opts.max_width,
    }
end

local function vspan(h) return VerticalSpan:new{ width = h } end
local function hspan(w) return HorizontalSpan:new{ width = w } end

local function nearest(list, v, key)
    local best, best_d = 1, math.huge
    for i, item in ipairs(list) do
        local x = key and item[key] or item
        if type(x) == "table" then x = x[1] end
        local vv = type(v) == "table" and v[1] or v
        local d = math.abs(x - vv)
        if d < best_d then best, best_d = i, d end
    end
    return best, best_d == 0
end

-- Tappable wrapper
local Tap = InputContainer:extend{ callback = nil }
function Tap:init()
    local s = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = s.w, h = s.h }
    self.ges_events = {
        TapItem = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end
function Tap:onTapItem()
    if self.callback then self.callback() end
    return true
end
local function tap(widget, cb) return Tap:new{ widget, callback = cb } end

-- Fixed-size rounded box with centered content; thick black border when selected.
local function box(content, w, h, opts)
    opts = opts or {}
    local bw = opts.selected and math.max(3, S(2)) or math.max(1, S(1))
    return FrameContainer:new{
        bordersize = bw,
        color = opts.selected and BLACK or MID,
        radius = opts.radius or S(8),
        padding = 0, margin = 0,
        background = WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * bw, h = h - 2 * bw }, content },
    }
end

-- Widget drawn by a function
local Paint = Widget:extend{ width = 0, height = 0, draw = nil }
function Paint:getSize() return Geom:new{ w = self.width, h = self.height } end
function Paint:paintTo(bb, x, y) self.draw(bb, x, y, self.width, self.height) end

local ICON_W, ICON_H = S(30), S(24)
local function lineThick() return math.max(2, S(1.2)) end

local function linesIcon(gap) -- line spacing
    return Paint:new{ width = ICON_W, height = ICON_H, draw = function(bb, x, y, w, h)
        local t, n = lineThick(), 4
        local total = n * t + (n - 1) * gap
        local y0 = y + math.floor((h - total) / 2)
        for i = 0, n - 1 do bb:paintRect(x, y0 + i * (t + gap), w, t, BLACK) end
    end }
end

local function marginIcon(side) -- page margins
    return Paint:new{ width = ICON_W, height = ICON_H + S(4), draw = function(bb, x, y, w, h)
        local t = lineThick()
        bb:paintBorder(x, y, w, h, math.max(1, S(1)), BLACK)
        local gap = math.floor((h - 4 * t) / 5)
        for i = 1, 4 do bb:paintRect(x + side, y + i * gap + (i - 1) * t, w - 2 * side, t, BLACK) end
    end }
end

local function alignIcon(justify)
    local widths = justify and { 1, 1, 1, 1 } or { 1, 0.7, 0.9, 0.55 }
    return Paint:new{ width = ICON_W, height = ICON_H, draw = function(bb, x, y, w, h)
        local t = lineThick()
        local gap = math.floor((h - 4 * t) / 3)
        for i = 1, 4 do bb:paintRect(x, y + (i - 1) * (t + gap), math.floor(w * widths[i]), t, BLACK) end
    end }
end

local function pageIcon(landscape)
    local w, h = S(16), S(22)
    if landscape then w, h = h, w end
    return Paint:new{ width = w, height = h, draw = function(bb, x, y, pw, ph)
        bb:paintBorder(x, y, pw, ph, math.max(2, S(1.2)), BLACK)
    end }
end

-- Slider with tick marks (font size, weight, contrast)
local Steps = InputContainer:extend{ n = 2, index = 1, width = 100, height = 40, callback = nil }
function Steps:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapStep = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        PanStep = { GestureRange:new{ ges = "pan", range = function() return self.dimen end } },
    }
end
function Steps:getSize() return Geom:new{ w = self.width, h = self.height } end
function Steps:radius() return math.floor(self.height * 0.28) end
function Steps:posX(i)
    local r = self:radius()
    return r + math.floor((i - 1) * (self.width - 2 * r) / (self.n - 1))
end
function Steps:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local r = self:radius()
    local cy = y + math.floor(self.height / 2)
    local x0, x1 = x + self:posX(1), x + self:posX(self.n)
    bb:paintRect(x0, cy - 1, x1 - x0, 2, MID)
    local tick = math.floor(r * 0.55)
    for i = 1, self.n do
        bb:paintRect(x + self:posX(i) - 1, cy - tick, 2, 2 * tick, MID)
    end
    local kx = x + self:posX(self.index)
    bb:paintRect(x0, cy - 2, kx - x0, 4, BLACK)
    bb:paintCircle(kx, cy, r, BLACK)
end
function Steps:pick(ges)
    local rel = (ges.pos.x - self.dimen.x - self:posX(1)) / (self:posX(self.n) - self:posX(1))
    local i = math.max(1, math.min(self.n, math.floor(rel * (self.n - 1) + 1.5)))
    if i ~= self.index and self.callback then self.callback(i) end
    return true
end
function Steps:onTapStep(_, ges) return self:pick(ges) end
function Steps:onPanStep() return true end -- don't let the page underneath scroll

local function getCre()
    return require("document/credocument"):engineInit()
end

local function fontFace(name, size)
    local ok, cre = pcall(getCre)
    if ok and cre then
        local file, idx = cre.getFontFaceFilenameAndFaceIndex(name)
        if not file then file, idx = cre.getFontFaceFilenameAndFaceIndex(name, nil, true) end
        if file then
            local face = Font:getFace(file, size, idx)
            if face then return face end
        end
    end
    return Font:getFace("cfont", size)
end

-- Run a settings change with KOReader's "Font size set to..." popups muted.
local function quietly(fn)
    Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_ICON)
    local ok, err = pcall(fn)
    Notification:resetNotifySource()
    if not ok then logger.warn("kindle-ui:", err) end
end

-------------------------------------------------------------------------------
-- "Aa" panel
-------------------------------------------------------------------------------

local TABS = { "Temas", "Fonte", "Layout", "Mais" }

local AaPanel = InputContainer:extend{ ui = nil, on_close = nil }
AaPanel.last_tab = 2 -- remembered while KOReader runs

function AaPanel:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.pad = S(18)
    self.inner_w = self.sw - 2 * self.pad
    self.tab = AaPanel.last_tab
    self.view = "tab"
    local full = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.ges_events = {
        TapPanel = { GestureRange:new{ ges = "tap", range = full } },
        SwipePanel = { GestureRange:new{ ges = "swipe", range = full } },
        HoldPanel = { GestureRange:new{ ges = "hold", range = full } },
        PanPanel = { GestureRange:new{ ges = "pan", range = full } },
    }
    -- The sheet keeps the height of the tallest tab, so it never jumps.
    local h = 0
    for i = 1, #TABS do
        h = math.max(h, self:buildTab(i):getSize().h)
    end
    self.body_h = h
    self:rebuild()
end

-- Current values ------------------------------------------------------------

function AaPanel:cfg() return self.ui.document.configurable end

function AaPanel:isLeftAligned()
    local st = self.ui.styletweak
    return st and (st:isTweakEnabled("text_align_most_left") or st:isTweakEnabled("text_align_all_left"))
end

-- Applying changes -----------------------------------------------------------

function AaPanel:set(name, value, event)
    quietly(function()
        self.ui:handleEvent(Event:new("ConfigChange", name, value))
        G_reader_settings:saveSetting("copt_" .. name, value) -- default for new books
        self.ui:handleEvent(Event:new(event, value))
    end)
end

function AaPanel:setFont(face)
    quietly(function()
        self.ui.font:onSetFont(face)
        self.ui.font:addToRecentlySelectedList(face)
        G_reader_settings:saveSetting("cre_font", face)
    end)
end

function AaPanel:setAlign(left)
    quietly(function()
        local st = self.ui.styletweak
        local L, J = "text_align_most_left", "text_align_most_justify"
        local g = st.global_tweaks
        if g == nil or g == require("ui/data/css_tweaks").DEFAULT_GLOBAL_STYLE_TWEAKS then
            g = {}
            for k, v in pairs(st.global_tweaks or {}) do g[k] = v end
            st.global_tweaks = g
        end
        g[L] = left or nil
        g[J] = (not left) or nil
        g.text_align_all_left = nil
        st.doc_tweaks[L], st.doc_tweaks[J], st.doc_tweaks.text_align_all_left = nil, nil, nil
        G_reader_settings:saveSetting("style_tweaks", g)
        st:updateCssText(true)
    end)
end

function AaPanel:applyTheme(t)
    local ui = self.ui
    ui:handleEvent(Event:new("BatchedUpdate")) -- re-render once, not per setting
    self:set("font_size", t.font_size, "SetFontSize")
    self:set("line_spacing", t.line_spacing, "SetLineSpace")
    self:set("h_page_margins", { t.margin, t.margin }, "SetPageHorizMargins")
    self:set("font_base_weight", t.weight, "SetFontBaseWeight")
    if t.font then self:setFont(t.font) end
    ui:handleEvent(Event:new("BatchedUpdateDone"))
end

function AaPanel:currentAsTheme()
    local c = self:cfg()
    return {
        name = "Meu tema",
        font = self.ui.font.font_face,
        font_size = c.font_size,
        line_spacing = c.line_spacing,
        margin = c.h_page_margins and c.h_page_margins[1] or 30,
        weight = c.font_base_weight or 0,
    }
end

function AaPanel:themeMatches(t)
    local c = self:cfg()
    return c.font_size == t.font_size and c.line_spacing == t.line_spacing
        and c.h_page_margins and c.h_page_margins[1] == t.margin
        and (c.font_base_weight or 0) == t.weight
        and (not t.font or t.font == self.ui.font.font_face)
end

-- Layout helpers -------------------------------------------------------------

function AaPanel:section(title, value, control)
    local dim = Geom:new{ w = self.inner_w, h = S(26) }
    local head = OverlapGroup:new{ dimen = dim:copy(),
        LeftContainer:new{ dimen = dim:copy(), text(title, 15, { bold = true }) } }
    if value then
        table.insert(head, RightContainer:new{ dimen = dim:copy(), text(value, 15, { color = GRAY }) })
    end
    return VerticalGroup:new{ align = "left", head, vspan(S(8)), control, vspan(S(16)) }
end

-- Row of equal boxes; make(i, selected) returns the box content.
function AaPanel:choices(n, selected, make, on_pick, h)
    local gap = S(10)
    local w = math.floor((self.inner_w - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i = 1, n do
        if i > 1 then table.insert(row, hspan(gap)) end
        local sel = (i == selected)
        table.insert(row, tap(box(make(i, sel), w, h or S(46), { selected = sel }), function()
            if not sel then on_pick(i); self:refresh() end
        end))
    end
    return row
end

local function labelled(icon, label, sel)
    return HorizontalGroup:new{ align = "center", icon, hspan(S(10)), text(label, 15, { bold = sel }) }
end

-- [−] left [====o====] right [+]
function AaPanel:slider(n, index, on_index, minus, plus, left_w, right_w)
    local bsz = S(40)
    local function round(label, cb)
        return tap(box(text(label, 22), bsz, bsz, { radius = math.floor(bsz / 2) }), function() cb(); self:refresh() end)
    end
    local side = S(10)
    local mid_w = self.inner_w - 2 * bsz - 4 * side - left_w:getSize().w - right_w:getSize().w
    return HorizontalGroup:new{ align = "center",
        round("−", minus), hspan(side), left_w, hspan(side),
        Steps:new{ n = n, index = index, width = mid_w, height = S(34),
            callback = function(i) on_index(i); self:refresh() end },
        hspan(side), right_w, hspan(side), round("+", plus),
    }
end

-- Tabs -----------------------------------------------------------------------

function AaPanel:buildTab(i)
    if i == 1 then return self:tabThemes()
    elseif i == 2 then return self:tabFont()
    elseif i == 3 then return self:tabLayout()
    else return self:tabMore() end
end

function AaPanel:tabFont()
    local c = self:cfg()
    local face = self.ui.font.font_face
    local bw = math.max(1, S(1))
    local dim = Geom:new{ w = self.inner_w - 2 * bw, h = S(54) }
    local font_button = tap(FrameContainer:new{
        bordersize = bw, color = MID, radius = S(8), padding = 0, margin = 0,
        OverlapGroup:new{ dimen = dim:copy(),
            LeftContainer:new{ dimen = dim:copy(), HorizontalGroup:new{ hspan(S(14)),
                text(face, 20, { face = fontFace(face, 20), max_width = dim.w - S(70) }) } },
            RightContainer:new{ dimen = dim:copy(), HorizontalGroup:new{ text("›", 26, { color = GRAY }), hspan(S(16)) } },
        },
    }, function() self.view = "fonts"; self.font_page = nil; self:refresh() end)

    local size = c.font_size
    local size_i = nearest(SIZES, size)
    local size_slider = self:slider(#SIZES, size_i,
        function(i) self:set("font_size", SIZES[i], "SetFontSize") end,
        function() self:set("font_size", math.max(12, size - 1), "SetFontSize") end,
        function() self:set("font_size", math.min(72, size + 1), "SetFontSize") end,
        text("Aa", 13, { face = fontFace(face, 13) }), text("Aa", 22, { face = fontFace(face, 22) }))

    local weight = c.font_base_weight or 0
    local w_i = nearest(WEIGHTS, weight)
    local weight_slider = self:slider(#WEIGHTS, w_i,
        function(i) self:set("font_base_weight", WEIGHTS[i], "SetFontBaseWeight") end,
        function() self:set("font_base_weight", WEIGHTS[math.max(1, w_i - 1)], "SetFontBaseWeight") end,
        function() self:set("font_base_weight", WEIGHTS[math.min(#WEIGHTS, w_i + 1)], "SetFontBaseWeight") end,
        text("A", 18, { color = GRAY }), text("A", 18, { bold = true }))
    local weight_label = weight == 0 and "normal" or string.format("%+g", weight):gsub("%.", ",")

    return VerticalGroup:new{ align = "left",
        self:section("Fonte", nil, font_button),
        self:section("Tamanho", tostring(size), size_slider),
        self:section("Espessura", weight_label, weight_slider),
    }
end

function AaPanel:tabLayout()
    local c = self:cfg()
    local landscape = Screen:getScreenMode() == "landscape"
    local orient = self:choices(2, landscape and 2 or 1,
        function(i, sel) return labelled(pageIcon(i == 2), i == 1 and "Retrato" or "Paisagem", sel) end,
        function(i)
            local mode = i == 2 and Screen.DEVICE_ROTATED_CLOCKWISE or Screen.DEVICE_ROTATED_UPRIGHT
            self:close()
            UIManager:nextTick(function()
                quietly(function()
                    self.ui:handleEvent(Event:new("ConfigChange", "rotation_mode", mode))
                    self.ui:handleEvent(Event:new("SetRotationMode", mode))
                end)
            end)
        end)

    local ls_i, ls_exact = nearest(LINE_SPACINGS, c.line_spacing)
    local gaps = { S(2), S(4), S(6) }
    local spacing = self:choices(3, ls_exact and ls_i or nil,
        function(i) return linesIcon(gaps[i]) end,
        function(i) self:set("line_spacing", LINE_SPACINGS[i], "SetLineSpace") end)

    local m = c.h_page_margins and c.h_page_margins[1] or 30
    local m_i, m_exact = nearest(MARGINS, m)
    local sides = { S(3), S(6), S(9) }
    local margins = self:choices(3, m_exact and m_i or nil,
        function(i) return marginIcon(sides[i]) end,
        function(i) self:set("h_page_margins", { MARGINS[i], MARGINS[i] }, "SetPageHorizMargins") end,
        S(52))

    local left = self:isLeftAligned()
    local align = self:choices(2, left and 1 or 2,
        function(i, sel) return labelled(alignIcon(i == 2), i == 1 and "À esquerda" or "Justificado", sel) end,
        function(i) self:setAlign(i == 1) end)

    return VerticalGroup:new{ align = "left",
        self:section("Orientação", nil, orient),
        self:section("Espaçamento entre linhas", c.line_spacing .. "%", spacing),
        self:section("Margens", nil, margins),
        self:section("Alinhamento", nil, align),
    }
end

function AaPanel:tabMore()
    local c = self:cfg()
    local rm_i = nearest(RENDER_MODES, c.block_rendering_mode or 2, 1)
    local render = self:choices(#RENDER_MODES, rm_i,
        function(i, sel) return text(RENDER_MODES[i][2], 15, { bold = sel }) end,
        function(i) self:set("block_rendering_mode", RENDER_MODES[i][1], "SetBlockRenderingMode") end)

    local ws_i, ws_exact = nearest(WORD_SPACINGS, c.word_spacing or WORD_SPACINGS[2][1], 1)
    local words = self:choices(#WORD_SPACINGS, ws_exact and ws_i or nil,
        function(i, sel) return text(WORD_SPACINGS[i][2], 15, { bold = sel }) end,
        function(i) self:set("word_spacing", WORD_SPACINGS[i][1], "SetWordSpacing") end)

    local g_i = nearest(GAMMAS, c.font_gamma or 15)
    local contrast = self:slider(#GAMMAS, g_i,
        function(i) self:set("font_gamma", GAMMAS[i], "SetFontGamma") end,
        function() self:set("font_gamma", GAMMAS[math.max(1, g_i - 1)], "SetFontGamma") end,
        function() self:set("font_gamma", GAMMAS[math.min(#GAMMAS, g_i + 1)], "SetFontGamma") end,
        text("A", 18, { color = MID }), text("A", 18))

    local all = tap(box(text("Todas as opções do KOReader  ›", 15), self.inner_w, S(46)), function()
        self:close()
        UIManager:nextTick(function() self.ui.config:showNativePanel() end)
    end)

    return VerticalGroup:new{ align = "left",
        self:section("Modo de renderização", nil, render),
        self:section("Espaço entre palavras", nil, words),
        self:section("Contraste", g_i .. " de " .. #GAMMAS, contrast),
        all,
    }
end

function AaPanel:tabThemes()
    local mine = G_reader_settings:readSetting("kindle_ui_my_theme")
    local list = {}
    for _, t in ipairs(THEMES) do table.insert(list, t) end
    table.insert(list, mine or { name = "Meu tema", empty = true })
    local sel
    for i, t in ipairs(list) do
        if not t.empty and self:themeMatches(t) then sel = i break end
    end
    local face = self.ui.font.font_face
    local cards = self:choices(#list, sel, function(i, is_sel)
        local t = list[i]
        local sample = t.empty and text("+", 30, { color = GRAY })
            or text("Aa", math.floor(t.font_size * 0.9), { face = fontFace(t.font or face, math.floor(t.font_size * 0.9)) })
        return VerticalGroup:new{ align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = S(60), h = S(52) }, sample },
            text(t.name, 14, { bold = is_sel }),
        }
    end, function(i)
        local t = list[i]
        if t.empty then
            G_reader_settings:saveSetting("kindle_ui_my_theme", self:currentAsTheme())
        else
            self:applyTheme(t)
        end
    end, S(100))

    local save = tap(box(text("Salvar ajustes atuais em \"Meu tema\"", 15), self.inner_w, S(46)), function()
        G_reader_settings:saveSetting("kindle_ui_my_theme", self:currentAsTheme())
        self:refresh()
    end)

    return VerticalGroup:new{ align = "left",
        self:section("Temas", nil, cards),
        TextBoxWidget:new{
            text = "Toque num tema para aplicar. \"Meu tema\" guarda fonte, tamanho, espaçamento, margens e espessura.",
            face = Font:getFace("cfont", 13), fgcolor = GRAY, width = self.inner_w,
        },
        vspan(S(16)),
        save,
    }
end

-- Font list ------------------------------------------------------------------

function AaPanel:faceList()
    if self._faces then return self._faces end
    local faces = {}
    local ok, cre = pcall(getCre)
    if ok and cre then
        for _, f in ipairs(cre.getFontFaces()) do
            local hidden = false
            for _, pat in ipairs(HIDDEN_FONTS) do
                if f:find(pat, 1, true) then hidden = true break end
            end
            if not hidden then table.insert(faces, f) end
        end
    end
    table.sort(faces, function(a, b) return a:lower() < b:lower() end)
    self._faces = faces
    return faces
end

function AaPanel:fontList()
    local faces = self:faceList()
    local current = self.ui.font.font_face
    local foot_h, row_h = S(44), S(54)
    local per_page = math.max(1, math.floor((self.body_h - foot_h) / row_h))
    local pages = math.max(1, math.ceil(#faces / per_page))
    if not self.font_page then
        local idx = 1
        for i, f in ipairs(faces) do if f == current then idx = i break end end
        self.font_page = math.floor((idx - 1) / per_page) + 1
    end
    self.font_page = math.max(1, math.min(pages, self.font_page))
    self.font_pages = pages

    local list = VerticalGroup:new{ align = "left" }
    for i = (self.font_page - 1) * per_page + 1, math.min(#faces, self.font_page * per_page) do
        local f = faces[i]
        local is_cur = f == current
        local rdim = Geom:new{ w = self.inner_w, h = row_h - 1 }
        local row = OverlapGroup:new{ dimen = rdim:copy(),
            LeftContainer:new{ dimen = rdim:copy(),
                text(f, 19, { face = fontFace(f, 19), max_width = self.inner_w - S(40) }) },
        }
        if is_cur then
            table.insert(row, RightContainer:new{ dimen = rdim:copy(), text("✓", 20, { bold = true }) })
        end
        table.insert(list, tap(VerticalGroup:new{ row,
            LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = 1 }, background = LIGHT } },
            function() if not is_cur then self:setFont(f); self:refresh() end end))
    end
    local listbox = OverlapGroup:new{ dimen = Geom:new{ w = self.inner_w, h = self.body_h - foot_h }, list }

    local fdim = Geom:new{ w = self.inner_w, h = foot_h }
    local foot = OverlapGroup:new{ dimen = fdim:copy(),
        CenterContainer:new{ dimen = fdim:copy(), text(self.font_page .. " de " .. pages, 15, { color = GRAY }) },
    }
    if self.font_page > 1 then
        table.insert(foot, LeftContainer:new{ dimen = fdim:copy(), tap(text("  ‹  ", 26), function() self:fontPage(-1) end) })
    end
    if self.font_page < pages then
        table.insert(foot, RightContainer:new{ dimen = fdim:copy(), tap(text("  ›  ", 26), function() self:fontPage(1) end) })
    end
    return VerticalGroup:new{ align = "left", listbox, foot }
end

function AaPanel:fontPage(delta)
    local p = (self.font_page or 1) + delta
    if p >= 1 and p <= (self.font_pages or 1) then
        self.font_page = p
        self:refresh()
    end
end

-- Sheet ----------------------------------------------------------------------

function AaPanel:rebuild()
    local top = VerticalGroup:new{ align = "center", vspan(S(10)),
        Paint:new{ width = S(44), height = S(5), draw = function(bb, x, y, w, h)
            bb:paintRoundedRect(x, y, w, h, MID, math.floor(h / 2))
        end },
        vspan(S(6)),
    }
    if self.view == "tab" then
        local tw = math.floor(self.sw / #TABS)
        local row = HorizontalGroup:new{}
        for i, name in ipairs(TABS) do
            local active = i == self.tab
            local label = text(name, 17, { bold = active, color = active and BLACK or GRAY })
            local under = active
                and CenterContainer:new{ dimen = Geom:new{ w = tw, h = S(3) },
                    LineWidget:new{ dimen = Geom:new{ w = label:getSize().w + S(20), h = S(3) }, background = BLACK } }
                or vspan(S(3))
            table.insert(row, tap(VerticalGroup:new{
                CenterContainer:new{ dimen = Geom:new{ w = tw, h = S(40) }, label }, under,
            }, function()
                self.tab = i
                AaPanel.last_tab = i
                self:refresh()
            end))
        end
        table.insert(top, row)
    else
        local hdim = Geom:new{ w = self.inner_w, h = S(43) }
        table.insert(top, HorizontalGroup:new{ hspan(self.pad), OverlapGroup:new{ dimen = hdim:copy(),
            CenterContainer:new{ dimen = hdim:copy(), text("Fonte", 17, { bold = true }) },
            LeftContainer:new{ dimen = hdim:copy(), tap(
                CenterContainer:new{ dimen = Geom:new{ w = S(110), h = S(43) }, text("‹  Voltar", 16) },
                function() self.view = "tab"; self:refresh() end) },
        }, hspan(self.pad) })
    end
    table.insert(top, LineWidget:new{ dimen = Geom:new{ w = self.sw, h = 1 }, background = LIGHT })

    local body = self.view == "fonts" and self:fontList() or self:buildTab(self.tab)
    self[1] = VerticalGroup:new{ align = "left",
        top,
        vspan(S(16)),
        HorizontalGroup:new{ hspan(self.pad), body },
    }
    self.sheet_h = top:getSize().h + S(16) + self.body_h + S(14)
    self.sheet_dimen = Geom:new{ x = 0, y = self.sh - self.sheet_h, w = self.sw, h = self.sheet_h }
end

function AaPanel:paintTo(bb, x, y)
    local sy = self.sh - self.sheet_h
    bb:paintRect(0, sy, self.sw, self.sheet_h, WHITE)
    bb:paintRect(0, sy, self.sw, math.max(1, S(1)), BLACK)
    self[1]:paintTo(bb, 0, sy)
end

function AaPanel:refresh()
    self:rebuild()
    UIManager:setDirty(self, function() return "ui", self.sheet_dimen end)
end

function AaPanel:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.sheet_dimen)
    if self.on_close then self.on_close() end
end

function AaPanel:onTapPanel(_, ges)
    if ges.pos.y < self.sheet_dimen.y then self:close() end
    return true
end

function AaPanel:onSwipePanel(_, ges)
    if ges.pos.y >= self.sheet_dimen.y then
        if ges.direction == "south" then
            self:close()
        elseif self.view == "fonts" and ges.direction == "west" then
            self:fontPage(1)
        elseif self.view == "fonts" and ges.direction == "east" then
            self:fontPage(-1)
        end
    else
        self:close()
    end
    return true
end

function AaPanel:onHoldPanel() return true end
function AaPanel:onPanPanel() return true end
function AaPanel:onClose() self:close() return true end -- Back key

-------------------------------------------------------------------------------
-- Table of contents ("Índice")
-------------------------------------------------------------------------------

local TocPage = InputContainer:extend{ ui = nil, covers_fullscreen = true }

function TocPage:init()
    local ui = self.ui
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.pad = S(20)
    self.inner_w = self.sw - 2 * self.pad
    ui.toc:fillToc()
    self.items = {}
    for i, item in ipairs(ui.toc.toc or {}) do
        if (item.depth or 1) <= 3 then
            table.insert(self.items, { toc = item, index = i })
        end
    end
    local cur_page = ui.document:getCurrentPage()
    local cur_index = ui.toc:getTocIndexByPage(cur_page)
    self.current = nil
    for k, it in ipairs(self.items) do
        if cur_index and it.index <= cur_index then self.current = k end
    end
    self.head_h, self.foot_h, self.row_h = S(84), S(56), S(54)
    self.per_page = math.max(1, math.floor((self.sh - self.head_h - self.foot_h) / self.row_h))
    self.pages = math.max(1, math.ceil(#self.items / self.per_page))
    self.page = self.current and math.floor((self.current - 1) / self.per_page) + 1 or 1
    local full = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.ges_events = {
        SwipeToc = { GestureRange:new{ ges = "swipe", range = full } },
        HoldToc = { GestureRange:new{ ges = "hold", range = full } },
        TapToc = { GestureRange:new{ ges = "tap", range = full } },
    }
    self:rebuild()
end

function TocPage:rebuild()
    local ui = self.ui
    local title = (ui.doc_props and ui.doc_props.display_title) or ""
    local hdim = Geom:new{ w = self.inner_w, h = S(52) }
    local head = VerticalGroup:new{ align = "left",
        vspan(S(10)),
        OverlapGroup:new{ dimen = hdim:copy(),
            CenterContainer:new{ dimen = hdim:copy(), VerticalGroup:new{ align = "center",
                text("Índice", 20, { bold = true }),
                text(title, 13, { color = GRAY, max_width = self.inner_w - S(120) }),
            } },
            LeftContainer:new{ dimen = hdim:copy(), tap(
                CenterContainer:new{ dimen = Geom:new{ w = S(52), h = S(52) }, text("✕", 22) },
                function() self:close() end) },
        },
        vspan(S(10)),
        LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = math.max(1, S(1)) }, background = BLACK },
        vspan(S(8)),
    }

    local list = VerticalGroup:new{ align = "left" }
    if #self.items == 0 then
        table.insert(list, vspan(S(40)))
        table.insert(list, CenterContainer:new{ dimen = Geom:new{ w = self.inner_w, h = S(40) },
            text("Este livro não tem índice.", 17, { color = GRAY }) })
    end
    local first = (self.page - 1) * self.per_page + 1
    for k = first, math.min(#self.items, first + self.per_page - 1) do
        local item = self.items[k].toc
        local is_cur = k == self.current
        local indent = S(22) * ((item.depth or 1) - 1)
        local page_txt = text(tostring(item.page or ""), 15, { color = GRAY })
        local pw = page_txt:getSize().w
        local rdim = Geom:new{ w = self.inner_w, h = self.row_h - 1 }
        local label = text(item.title or "", 17, { bold = is_cur,
            max_width = self.inner_w - indent - pw - S(40) })
        local row = OverlapGroup:new{ dimen = rdim:copy(),
            LeftContainer:new{ dimen = rdim:copy(), HorizontalGroup:new{ hspan(S(14) + indent), label } },
            RightContainer:new{ dimen = rdim:copy(), page_txt },
        }
        if is_cur then
            table.insert(row, LeftContainer:new{ dimen = rdim:copy(),
                LineWidget:new{ dimen = Geom:new{ w = S(4), h = math.floor(self.row_h * 0.6) }, background = BLACK } })
        end
        table.insert(list, tap(VerticalGroup:new{ row,
            LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = 1 }, background = LIGHT } },
            function() self:goTo(item) end))
    end

    local fdim = Geom:new{ w = self.inner_w, h = self.foot_h }
    local foot = OverlapGroup:new{ dimen = fdim:copy(),
        CenterContainer:new{ dimen = fdim:copy(), text(self.page .. " de " .. self.pages, 15, { color = GRAY }) },
    }
    if self.page > 1 then
        table.insert(foot, LeftContainer:new{ dimen = fdim:copy(), tap(text("  ‹  ", 28), function() self:turn(-1) end) })
    end
    if self.page < self.pages then
        table.insert(foot, RightContainer:new{ dimen = fdim:copy(), tap(text("  ›  ", 28), function() self:turn(1) end) })
    end

    self[1] = HorizontalGroup:new{ hspan(self.pad), VerticalGroup:new{ align = "left",
        head,
        OverlapGroup:new{ dimen = Geom:new{ w = self.inner_w, h = self.sh - self.head_h - self.foot_h }, list },
        foot,
    } }
end

function TocPage:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.sw, self.sh, WHITE)
    self[1]:paintTo(bb, 0, 0)
end

function TocPage:turn(delta)
    local p = self.page + delta
    if p >= 1 and p <= self.pages then
        self.page = p
        self:rebuild()
        UIManager:setDirty(self, "ui")
    end
end

function TocPage:goTo(item)
    self:close()
    local ui = self.ui
    ui.link:addCurrentLocationToStack()
    if item.xpointer then
        ui:handleEvent(Event:new("GotoXPointer", item.xpointer, item.xpointer))
    else
        ui:handleEvent(Event:new("GotoPage", item.page))
    end
end

function TocPage:close()
    UIManager:close(self, "flashui")
end

function TocPage:onSwipeToc(_, ges)
    if ges.direction == "west" then self:turn(1)
    elseif ges.direction == "east" then self:turn(-1)
    elseif ges.direction == "south" and ges.pos.y < self.head_h then self:close() end
    return true
end
function TocPage:onHoldToc() return true end
function TocPage:onTapToc() return true end
function TocPage:onClose() self:close() return true end

-------------------------------------------------------------------------------
-- Top toolbar
-------------------------------------------------------------------------------

local Toolbar = InputContainer:extend{ ui = nil }

function Toolbar:init()
    local ui = self.ui
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    local full = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.ges_events = {
        TapBar = { GestureRange:new{ ges = "tap", range = full } },
        SwipeBar = { GestureRange:new{ ges = "swipe", range = full } },
        HoldBar = { GestureRange:new{ ges = "hold", range = full } },
    }

    local marked = false
    pcall(function()
        marked = ui.bookmark:isPageBookmarked(ui.bookmark:getCurrentPageNumber()) and true or false
    end)

    local function act(fn)
        return function()
            self:close()
            UIManager:nextTick(fn)
        end
    end
    local buttons = {
        { "home", "Biblioteca", act(function() ui:handleEvent(Event:new("Home")) end) },
        { "appbar.navigation", "Índice", act(function() UIManager:show(TocPage:new{ ui = ui }, "flashui") end) },
        { nil, "Fonte", act(function() ui:handleEvent(Event:new("ShowConfigMenu")) end) },
        { "appbar.search", "Buscar", act(function() ui:handleEvent(Event:new("ShowFulltextSearchInput")) end) },
        { marked and "star.full" or "star.empty", marked and "Desmarcar" or "Marcar",
            act(function() ui:handleEvent(Event:new("ToggleBookmark")) end) },
        { "appbar.menu", "Menu", act(function() ui.menu:onShowMenu() end) },
    }
    local bw = math.floor(self.sw / #buttons)
    local isz = S(30)
    local row = HorizontalGroup:new{}
    for _, b in ipairs(buttons) do
        local icon = b[1] and IconWidget:new{ icon = b[1], width = isz, height = isz }
            or CenterContainer:new{ dimen = Geom:new{ w = isz, h = isz }, text("Aa", 22, { bold = true }) }
        table.insert(row, tap(CenterContainer:new{ dimen = Geom:new{ w = bw, h = S(72) },
            VerticalGroup:new{ align = "center", icon, vspan(S(5)), text(b[2], 13) } }, b[3]))
    end

    local title = (ui.doc_props and ui.doc_props.display_title) or ""
    local chapter = ""
    pcall(function() chapter = ui.toc:getTocTitleByPage(ui.document:getCurrentPage()) or "" end)
    local info = chapter ~= "" and chapter or title
    self[1] = VerticalGroup:new{ align = "center",
        vspan(S(8)),
        CenterContainer:new{ dimen = Geom:new{ w = self.sw, h = S(28) },
            text(info, 15, { bold = true, max_width = self.sw - S(40) }) },
        row,
        vspan(S(4)),
    }
    self.bar_h = self[1]:getSize().h
    self.bar_dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.bar_h + S(2) }
end

function Toolbar:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.sw, self.bar_h, WHITE)
    bb:paintRect(0, self.bar_h, self.sw, math.max(2, S(1.5)), BLACK)
    self[1]:paintTo(bb, 0, 0)
end

function Toolbar:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.bar_dimen)
end

function Toolbar:onTapBar() self:close() return true end
function Toolbar:onSwipeBar() self:close() return true end
function Toolbar:onHoldBar() return true end
function Toolbar:onClose() self:close() return true end

-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------

local function isCre(ui) return ui and ui.rolling and ui.document and not ui.document.koptinterface end

local orig_showConfig = ReaderConfig.onShowConfigMenu
function ReaderConfig:showNativePanel()
    return orig_showConfig(self)
end
ReaderConfig.onShowConfigMenu = function(self)
    if not isCre(self.ui) then return orig_showConfig(self) end
    if self.aa_panel then return true end
    if self.ui.keyselection then pcall(function() self.ui.keyselection:stopHighlightIndicator(true) end) end
    self.ui:handleEvent(Event:new("DisableHinting"))
    self.aa_panel = AaPanel:new{ ui = self.ui, on_close = function()
        self.aa_panel = nil
        self.ui:handleEvent(Event:new("RestoreHinting"))
    end }
    UIManager:show(self.aa_panel, "ui", self.aa_panel.sheet_dimen)
    self.ui:handleEvent(Event:new("HandledAsSwipe"))
    return true
end

local orig_closeConfig = ReaderConfig.onCloseConfigMenu
ReaderConfig.onCloseConfigMenu = function(self)
    if self.aa_panel then self.aa_panel:close() end
    return orig_closeConfig(self)
end

local function showToolbar(ui)
    local bar = Toolbar:new{ ui = ui }
    UIManager:show(bar, "ui", bar.bar_dimen)
end

local orig_tapMenu = ReaderMenu.onTapShowMenu
ReaderMenu.onTapShowMenu = function(self, ges)
    if isCre(self.ui) and self.activation_menu ~= "swipe" then
        showToolbar(self.ui)
        return true
    end
    return orig_tapMenu(self, ges)
end

local orig_swipeMenu = ReaderMenu.onSwipeShowMenu
ReaderMenu.onSwipeShowMenu = function(self, ges)
    if isCre(self.ui) and self.activation_menu ~= "tap" and ges.direction == "south" then
        showToolbar(self.ui)
        return true
    end
    return orig_swipeMenu(self, ges)
end
