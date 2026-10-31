--[[
Kindle-style top bar for EPUB/CRE books.

  [ 12 min restantes ]        [ 12:45 ]        [ 42% ]

* Space is reserved: the bar height is added to the book's top margin,
  so text never runs under it.
* Long-press on the bar opens the reading style panel (native ReaderConfig).
* The clock refreshes once per minute, only while the book page is on top.
* No battery, no title, no visible button.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderView = require("apps/reader/modules/readerview")

local FONT_SIZE = 16                       -- a bit bigger than KOReader's footer (14)
local BAR_H = Screen:scaleBySize(26)       -- reserved band height
local BAR_GAP = Screen:scaleBySize(6)      -- space between bar and text
local BOTTOM_M = BAR_GAP                    -- bottom margin = top gap (symmetric)
local LINE_W = 1                           -- divider thickness (px)

local function barEnabled(view)
    return view.ui and view.ui.rolling and view.view_mode == "page"
end

local function chapterTimeLeft(ui, pageno)
    local stats = ui.statistics
    if not (stats and stats.settings and stats.settings.is_enabled) then return "" end
    local avg = stats.avg_time
    if not avg or avg ~= avg or avg <= 0 then return "" end
    local left = ui.toc:getChapterPagesLeft(pageno, true) or ui.document:getTotalPagesLeft(pageno)
    if not left then return "" end
    local mins = math.floor(left * avg / 60 + 0.5)
    if mins < 1 then
        return "menos de 1 min restante"
    elseif mins < 60 then
        return mins .. " min restantes"
    end
    local h, m = math.floor(mins / 60), mins % 60
    if m == 0 then return h .. " h restantes" end
    return string.format("%d h %d min restantes", h, m)
end

local function paintBar(view, bb, x, y)
    local ui = view.ui
    local footer = view.footer
    local pageno = footer and footer.pageno or ui.document:getCurrentPage()
    local pct = footer and footer.percent_finished
    if not pct then
        local total = ui.document:getPageCount()
        pct = total > 0 and pageno / total or 0
    end

    local w = Screen:getWidth()
    local pad = Screen:scaleBySize(ui.document.configurable.h_page_margins
        and ui.document.configurable.h_page_margins[1] or 15)
    local face = Font:getFace("ffont", FONT_SIZE)

    -- Wipe the whole top margin, not just the bar: crengine can leak the
    -- descenders of the previous page's last line into the margin.
    bb:paintRect(x, y, w, view._kh_top or (BAR_H + BAR_GAP), Blitbuffer.COLOR_WHITE)

    local clock = TextWidget:new{
        text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
        face = face,
    }
    local cw = clock:getSize().w
    local side_max = math.floor((w - cw) / 2) - pad - Screen:scaleBySize(8)

    local left = TextWidget:new{ text = chapterTimeLeft(ui, pageno), face = face, max_width = side_max }
    local right = TextWidget:new{ text = string.format("%d%%", math.floor(pct * 100)), face = face, max_width = side_max }

    local function vy(widget) return y + math.floor((BAR_H - widget:getSize().h) / 2) end
    left:paintTo(bb, x + pad, vy(left))
    clock:paintTo(bb, x + math.floor((w - cw) / 2), vy(clock))
    right:paintTo(bb, x + w - pad - right:getSize().w, vy(right))
    left:free(); clock:free(); right:free()

    -- Thin divider at the bottom of the bar, aligned with the text margins.
    bb:paintRect(x + pad, y + BAR_H - LINE_W, w - 2 * pad, LINE_W, Blitbuffer.COLOR_BLACK)
end

-- 0. Keep crengine's own top status bar (title + chapter marks) off:
--    it would draw under our bar and take extra space.
--    (crengine: status_line 0 = header on, 1 = off)
G_reader_settings:saveSetting("copt_status_line", 1)
local orig_onSetStatusLine = ReaderRolling.onSetStatusLine
ReaderRolling.onSetStatusLine = function(self, status_line)
    if self.ui.document and self.ui.document.configurable then
        self.ui.document.configurable.status_line = 1
    end
    return orig_onSetStatusLine(self, 1)
end

-- 1. Reserve the band: the bar replaces the book's top margin.
--    BAR_GAP may be negative: the first text line has blank space above its
--    letters, and the bar text has blank space below its baseline.
local orig_setPageMargins = ReaderTypeset.onSetPageMargins
ReaderTypeset.onSetPageMargins = function(self, margins, when_applied_callback)
    local orig_doc_set = self.ui.document.setPageMargins
    self.ui.document.setPageMargins = function(doc, l, t, r, b)
        if self.view.view_mode == "page" then t = BAR_H + BAR_GAP; b = BOTTOM_M end
        self.view._kh_top = t -- where the text starts; everything above is wiped
        return orig_doc_set(doc, l, t, r, b)
    end
    local ok, err = pcall(orig_setPageMargins, self, margins, when_applied_callback)
    self.ui.document.setPageMargins = orig_doc_set
    if not ok then error(err) end
end

-- 2. Paint the bar inside the reserved band.
local orig_paintTo = ReaderView.paintTo
ReaderView.paintTo = function(self, bb, x, y)
    orig_paintTo(self, bb, x, y)
    if barEnabled(self) then
        local ok, err = pcall(paintBar, self, bb, x, y)
        if not ok then require("logger").warn("kindle-header paint:", err) end
    end
end

-- 3. Long-press on the bar -> style panel. 4. Clock refresh every minute.
local orig_onReaderReady = ReaderTypeset.onReaderReady
ReaderTypeset.onReaderReady = function(self, ...)
    if orig_onReaderReady then orig_onReaderReady(self, ...) end
    local ui, view = self.ui, self.view

    ui:registerTouchZones({
        {
            id = "kindle_header_hold",
            ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = BAR_H / Screen:getHeight() },
            handler = function()
                if not barEnabled(view) then return end
                ui:handleEvent(Event:new("ShowConfigMenu"))
                return true
            end,
            overrides = { "readerhighlight_hold" },
        },
    })

    self._kh_tick = function()
        if not ui.document then return end
        local top = UIManager:getTopmostVisibleWidget() or {}
        if top.name == "ReaderUI" and barEnabled(view) then
            UIManager:setDirty(view.dialog, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = BAR_H })
        end
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self._kh_tick)
    end
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self._kh_tick)
end

local orig_onCloseDocument = ReaderTypeset.onCloseDocument
ReaderTypeset.onCloseDocument = function(self, ...)
    if self._kh_tick then UIManager:unschedule(self._kh_tick) end
    if orig_onCloseDocument then return orig_onCloseDocument(self, ...) end
end
