--[[
Kindle-style home screen, shown on top of KOReader's file manager.

Styles (setting "kindle_home_style", or hold the title to choose):
  "minimal_estante" (default) - clock, book being read, other books in progress
  "minimal" - clock, book being read, quote of the day (both read only the history: fast)
  "painel" / "dados" / "estante" - module screens (clock, stats, reading goal, heatmap, cover shelf...)
  "inicio" - Kindle home: book being read in a big card, rows of recent and unread books
  "grade"  - library as a cover grid with filters (Todos / Lendo / Não lidos / Lidos)
  "lista"  - library as a list with small covers and progress

Bottom bar: Início (style "inicio" only) · Biblioteca · Arquivos (KOReader's file browser) · Menu.
Tap a book to open it. The house icon of the file browser brings this screen back.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local function S(px) return Screen:scaleBySize(px) end

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY = Blitbuffer.COLOR_GRAY_5
local MID = Blitbuffer.COLOR_GRAY_9
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY
local PALE = Blitbuffer.COLOR_GRAY_E

local function style() return G_reader_settings:readSetting("kindle_home_style") or "estante_relogio" end
-- Styles that only need the reading history (fast, no folder scan)
local HISTORY_ONLY = { minimal = true, minimal_estante = true, estante_relogio = true }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function text(str, size, opts)
    opts = opts or {}
    return TextWidget:new{
        text = str or "", face = Font:getFace(opts.font or "cfont", size),
        bold = opts.bold, fgcolor = opts.color or BLACK, max_width = opts.max_width,
    }
end

local function textbox(str, size, width, lines, opts)
    opts = opts or {}
    local face = Font:getFace(opts.font or "cfont", size)
    return TextBoxWidget:new{
        text = str or "", face = face, width = width, bold = opts.bold,
        fgcolor = opts.color or BLACK, alignment = opts.alignment or "left", bgcolor = opts.bg,
        height = lines and math.ceil(lines * face.size * 1.35) or nil,
        height_adjust = true, height_overflow_show_ellipsis = true,
    }
end

local function vspan(h) return VerticalSpan:new{ width = h } end
local function hspan(w) return HorizontalSpan:new{ width = w } end

local Tap = InputContainer:extend{ callback = nil }
function Tap:init()
    local s = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = s.w, h = s.h }
    self.ges_events = { TapItem = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end
function Tap:onTapItem() if self.callback then self.callback() end return true end
local function tap(w, cb) return Tap:new{ w, callback = cb } end

local Paint = Widget:extend{ width = 0, height = 0, draw = nil }
function Paint:getSize() return Geom:new{ w = self.width, h = self.height } end
function Paint:paintTo(bb, x, y) self.draw(bb, x, y, self.width, self.height) end

local function progressBar(w, pct, h)
    h = h or math.max(3, S(3))
    return Paint:new{ width = w, height = h, draw = function(bb, x, y, pw, ph)
        bb:paintRect(x, y, pw, ph, LIGHT)
        if pct and pct > 0 then bb:paintRect(x, y, math.floor(pw * math.min(1, pct)), ph, BLACK) end
    end }
end

local function fixed(w, h, widget, align)
    local C = align == "left" and LeftContainer or (align == "right" and RightContainer or CenterContainer)
    return C:new{ dimen = Geom:new{ w = w, h = h }, widget }
end

-------------------------------------------------------------------------------
-- Library data
-------------------------------------------------------------------------------

-- CoverBrowser's cover/metadata cache. Loaded on first use: plugins are not
-- on package.path yet when patches run.
local BookInfoManager
local function BIM()
    if BookInfoManager == nil then
        local ok, bim = pcall(require, "bookinfomanager")
        BookInfoManager = ok and bim or false
    end
    return BookInfoManager or nil
end
local BookList = require("ui/widget/booklist")
local ReadHistory = require("readhistory")

local Library = {}

function Library.scan()
    local root = G_reader_settings:readSetting("home_dir") or Device.home_dir or "/"
    local books = {}
    local function walk(dir, depth)
        local ok, iter, obj = pcall(lfs.dir, dir)
        if not ok then return end
        for name in iter, obj do
            if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
                local path = dir .. "/" .. name
                local mode = lfs.attributes(path, "mode")
                if mode == "directory" and depth < 3 then
                    walk(path, depth + 1)
                elseif mode == "file" and DocumentRegistry:hasProvider(path) then
                    table.insert(books, { file = path, name = name,
                        mtime = lfs.attributes(path, "modification") or 0 })
                end
            end
        end
    end
    walk(root, 0)
    local last_read = {}
    for _, h in ipairs(ReadHistory.hist or {}) do
        if h.file and not last_read[h.file] then last_read[h.file] = h.time or 0 end
    end
    for _, b in ipairs(books) do
        b.read_time = last_read[b.file]
        local info = BookList.getBookInfo(b.file)
        b.status = BookList.getBookStatus(b.file)
        b.percent = info and info.percent_finished or 0
        if b.status == "complete" then b.percent = 1 end
        Library.meta(b)
    end
    table.sort(books, function(a, b)
        if (a.read_time or 0) ~= (b.read_time or 0) then return (a.read_time or 0) > (b.read_time or 0) end
        return a.mtime > b.mtime
    end)
    return books
end

-- Fast path: only books from the reading history (no folder scan).
function Library.recent(max)
    local books, seen = {}, {}
    for _, h in ipairs(ReadHistory.hist or {}) do
        if #books >= (max or 12) then break end
        local f = h.file
        if f and not seen[f] and lfs.attributes(f, "mode") == "file" then
            seen[f] = true
            local b = { file = f, name = f:match("([^/]+)$"), mtime = 0, read_time = h.time or 0 }
            local info = BookList.getBookInfo(f)
            b.status = BookList.getBookStatus(f)
            b.percent = info and info.percent_finished or 0
            if b.status == "complete" then b.percent = 1 end
            Library.meta(b)
            table.insert(books, b)
        end
    end
    books.partial = true
    return books
end

function Library.meta(b)
    b.title = b.name:gsub("%.[^.]+$", ""):gsub("[_]", " ")
    b.author = ""
    if not BIM() then return end
    local info = BIM():getBookInfo(b.file, true)
    if info and info.has_meta then
        if info.title and info.title ~= "" then
            -- "Os Maias: episodios da vida romantica" -> "Os Maias"
            b.title = info.title:gsub("%s*[:/]%s.*$", ""):gsub("%s*[:/]$", "")
        end
        if info.authors then b.author = info.authors:gsub("\n", ", ") end
    end
    if info and info.has_cover and info.cover_bb then
        b.cover_bb, b.cover_w, b.cover_h = info.cover_bb, info.cover_w, info.cover_h
    end
    b.missing = not info or (info.in_progress and info.in_progress ~= 0) or not info.cover_fetched
end

function Library.extractMissing(books, on_done)
    local BookInfoManager = BIM()
    if not BookInfoManager then return end
    local todo = {}
    for _, b in ipairs(books) do
        if b.missing then
            table.insert(todo, { filepath = b.file, cover_specs = { max_cover_w = S(260), max_cover_h = S(380) } })
        end
    end
    if #todo == 0 then return end
    BookInfoManager:extractInBackground(todo)
    local function poll()
        if BookInfoManager:isExtractingInBackground() then
            UIManager:scheduleIn(1, poll)
        else
            on_done()
        end
    end
    UIManager:scheduleIn(1, poll)
end

-- Cover image fitted in w x h; generated cover when the book has none.
local function cover(b, w, h)
    if b.cover_bb and b.cover_w and b.cover_w > 0 then
        local sf = math.min(w / b.cover_w, h / b.cover_h)
        local img = ImageWidget:new{ image = b.cover_bb, image_disposable = false, scale_factor = sf }
        img:_render()
        local s = img:getSize()
        return fixed(w, h, FrameContainer:new{ bordersize = math.max(1, S(0.6)), color = LIGHT,
            padding = 0, margin = 0, img }), s
    end
    local inner = w - 2 * S(8)
    return FrameContainer:new{
        bordersize = math.max(1, S(1)), color = MID, padding = 0, margin = 0, background = PALE,
        fixed(w - 2 * math.max(1, S(1)), h - 2 * math.max(1, S(1)), VerticalGroup:new{ align = "center",
            textbox(b.title, math.max(9, math.floor(w / S(9))), inner, 4, { font = "NotoSerif-Bold.ttf", alignment = "center", bg = PALE }),
            vspan(S(6)),
            textbox(b.author, math.max(8, math.floor(w / S(12))), inner, 2, { alignment = "center", color = GRAY, bg = PALE }),
        }),
    }
end

-------------------------------------------------------------------------------
-- Home widget
-------------------------------------------------------------------------------

local Home = InputContainer:extend{ covers_fullscreen = true, is_always_active = false }

function Home:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.pad = S(18)
    self.inner_w = self.sw - 2 * self.pad
    self.view = (style() == "grade" or style() == "lista") and "biblioteca" or "inicio"
    self.filter = "todos"
    self.page = 1
    local full = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.ges_events = {
        SwipeHome = { GestureRange:new{ ges = "swipe", range = full } },
        HoldHome = { GestureRange:new{ ges = "hold", range = full } },
        TapHome = { GestureRange:new{ ges = "tap", range = full } },
    }
    self:reload()
    self.tick = function()
        if self.closed then return end
        local spot = self.clock_spot
        if spot and spot.pos and UIManager:getTopmostVisibleWidget() == self then
            local region = spot.pos
            self:rebuild()
            UIManager:setDirty(self, "ui", region)
        end
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.tick)
    end
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.tick)
    Library.extractMissing(self.books, function()
        if self.closed then return end
        self:reload()
        self:refresh("ui")
    end)
end

function Home:reload()
    if self.view == "inicio" and HISTORY_ONLY[style()] then
        self.books = Library.recent()
    else
        self.books = Library.scan()
    end
    self:rebuild()
end

function Home:open(b)
    self:close()
    UIManager:nextTick(function()
        require("apps/reader/readerui"):showReader(b.file)
    end)
end

-- Top and bottom bars -----------------------------------------------------------

function Home:topBar(title)
    local h = S(64)
    local dim = Geom:new{ w = self.inner_w, h = h }
    local search = tap(fixed(S(48), h, IconWidget:new{ icon = "appbar.search", width = S(28), height = S(28) }),
        function()
            self:close()
            UIManager:nextTick(function()
                local fm = FileManager.instance
                if fm and fm.filesearcher then fm.filesearcher:onShowFileSearch() end
            end)
        end)
    return VerticalGroup:new{
        HorizontalGroup:new{ hspan(self.pad), OverlapGroup:new{ dimen = dim:copy(),
            LeftContainer:new{ dimen = dim:copy(), text(title, 24, { bold = true }) },
            RightContainer:new{ dimen = dim:copy(), search },
        } },
    }
end

function Home:navBar()
    local items = {}
    if style() ~= "grade" and style() ~= "lista" then
        table.insert(items, { "home", "Início", "inicio" })
    end
    table.insert(items, { "book.opened", "Biblioteca", "biblioteca" })
    table.insert(items, { "appbar.filebrowser", "Arquivos", "arquivos" })
    table.insert(items, { "appbar.menu", "Menu", "menu" })
    local w = math.floor(self.sw / #items)
    local row = HorizontalGroup:new{}
    for _, it in ipairs(items) do
        local active = it[3] == self.view
        local cell = VerticalGroup:new{ align = "center",
            IconWidget:new{ icon = it[1], width = S(26), height = S(26) },
            vspan(S(4)),
            text(it[2], 13, { bold = active, color = active and BLACK or GRAY }),
        }
        table.insert(row, tap(fixed(w, S(66), cell), function() self:nav(it[3]) end))
    end
    return VerticalGroup:new{
        LineWidget:new{ dimen = Geom:new{ w = self.sw, h = math.max(1, S(1)) }, background = BLACK },
        row,
    }
end

function Home:nav(target)
    if target == "arquivos" then
        self:close()
    elseif target == "menu" then
        local fm = FileManager.instance
        if fm and fm.menu then fm.menu:onShowMenu() end
    elseif target ~= self.view then
        self.view = target
        self.page = 1
        if target == "biblioteca" and self.books.partial then self:reload() else self:rebuild() end
        self:refresh("flashui")
    end
end

function Home:sectionTitle(title, right)
    local dim = Geom:new{ w = self.inner_w, h = S(36) }
    local g = OverlapGroup:new{ dimen = dim:copy(),
        LeftContainer:new{ dimen = dim:copy(), text(title, 18, { bold = true }) } }
    if right then table.insert(g, RightContainer:new{ dimen = dim:copy(), right }) end
    return g
end

-- Module home screens ("painel", "minimal", "dados", "estante") -----------------------

local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local Event = require("ui/event")

local PRESETS = {
    painel  = { "clock_small", "current", "recent", "actions" },
    minimal = { "clock_big", "current_hero", "quote" },
    minimal_estante = { "clock_mid", "current_hero_mid", "also_reading" },
    estante_relogio = { "clock_line", "current", "reading_deck", "quote" },
    dados   = { "current", "goal", "stats", "heatmap" },
    estante = { "current", "deck", "quote" },
}

local WEEKDAYS = { "domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado" }
local MONTHS = { "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto",
    "setembro", "outubro", "novembro", "dezembro" }

-- Public-domain lines used when there are no highlights yet.
local QUOTES = {
    { "Tudo vale a pena se a alma não é pequena.", "Fernando Pessoa, Mar Português" },
    { "Ao vencedor, as batatas!", "Machado de Assis, Quincas Borba" },
    { "Amor é fogo que arde sem se ver.", "Luís de Camões" },
    { "Tenho em mim todos os sonhos do mundo.", "Álvaro de Campos, Tabacaria" },
    { "Sobre a nudez forte da verdade, o manto diáfano da fantasia.", "Eça de Queirós, A Relíquia" },
}

local function fmtDuration(sec)
    sec = math.floor(sec or 0)
    if sec < 60 then return "0 min" end
    local m = math.floor(sec / 60)
    if m < 60 then return m .. " min" end
    local h, mm = math.floor(m / 60), m % 60
    return mm == 0 and (h .. " h") or string.format("%d h %d min", h, mm)
end

local function agoText(t)
    if not t then return nil end
    local today = os.date("*t")
    local d0 = os.time{ year = today.year, month = today.month, day = today.day, hour = 0 }
    if t >= d0 then return "Lido hoje" end
    local days = math.floor((d0 - t) / 86400) + 1
    if days == 1 then return "Lido ontem" end
    return "Lido há " .. days .. " dias"
end

-- Reading statistics (statistics plugin database) ------------------------------------
local Stats = {}

function Stats.query(fn)
    local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok_lib, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_lib then return nil end
    local ok_open, conn = pcall(SQ3.open, path)
    if not ok_open or not conn then return nil end
    local ok, res = pcall(fn, conn)
    pcall(conn.close, conn)
    if not ok then logger.warn("kindle-home stats:", res) return nil end
    return res
end

function Stats.daily(days)
    local since = os.time() - days * 86400
    return Stats.query(function(conn)
        local res = conn:exec(string.format([[SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime'),
            sum(duration) FROM page_stat_data WHERE start_time >= %d GROUP BY 1]], since))
        local out = {}
        if res then
            for i = 1, #res[1] do out[res[1][i]] = tonumber(res[2][i]) or 0 end
        end
        return out
    end) or {}
end

function Stats.secondsPerPage(md5)
    return Stats.query(function(conn)
        local t, p
        if md5 then
            t, p = conn:rowexec(string.format(
                "SELECT total_read_time, total_read_pages FROM book WHERE md5 = '%s' ORDER BY last_open DESC LIMIT 1",
                (md5:gsub("'", ""))))
        end
        if not (tonumber(t) and tonumber(p) and tonumber(p) > 0) then
            t, p = conn:rowexec("SELECT sum(total_read_time), sum(total_read_pages) FROM book")
        end
        t, p = tonumber(t), tonumber(p)
        if t and p and p > 0 then return t / p end
    end)
end

function Library.details(b)
    if b._details then return b._details end
    local d = {}
    local ok, ds = pcall(DocSettings.open, DocSettings, b.file)
    if ok and ds then
        d.pages = ds:readSetting("doc_pages") or (ds:readSetting("stats") or {}).pages
        d.md5 = ds:readSetting("partial_md5_checksum")
        local summary = ds:readSetting("summary") or {}
        d.finished_on = summary.modified
        d.annotations = ds:readSetting("annotations")
    end
    b._details = d
    return d
end

-- Reading time left (only computed for the books that show it).
function Library.timeLeft(b)
    local d = Library.details(b)
    if d.left == nil then
        d.left = false
        if d.pages and b.percent and b.percent < 1 then
            local spp = Stats.secondsPerPage(d.md5)
            if spp then d.left = d.pages * (1 - b.percent) * spp end
        end
    end
    return d.left or nil
end

-- Small widgets -------------------------------------------------------------------------

local UPPER = { ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í",
    ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function label(str)
    local up = str:upper():gsub("\195[\128-\191]", function(c) return UPPER[c] or c end)
    return text(up, 12, { bold = true, color = GRAY })
end

local function glyph(kind, size)
    return Paint:new{ width = size, height = size, draw = function(bb, x, y, w, h)
        local cx, cy, r = x + math.floor(w / 2), y + math.floor(h / 2), math.floor(w / 2)
        local t = math.max(2, S(1.4))
        if kind == "sun" then
            bb:paintCircle(cx, cy, math.floor(r * 0.42), BLACK, t)
            for i = 0, 7 do
                local a = i * math.pi / 4
                local x1, y1 = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
                local x2, y2 = cx + math.cos(a) * r * 0.92, cy + math.sin(a) * r * 0.92
                for k = 0, 6 do
                    local px = math.floor(x1 + (x2 - x1) * k / 6)
                    local py = math.floor(y1 + (y2 - y1) * k / 6)
                    bb:paintRect(px - 1, py - 1, t, t, BLACK)
                end
            end
        elseif kind == "moon" then
            bb:paintCircle(cx, cy, math.floor(r * 0.8), BLACK)
            bb:paintCircle(cx + math.floor(r * 0.38), cy - math.floor(r * 0.3), math.floor(r * 0.68), WHITE)
        elseif kind == "clock" then
            bb:paintCircle(cx, cy, math.floor(r * 0.85), BLACK, t)
            bb:paintRect(cx - math.floor(t / 2), cy - math.floor(r * 0.55), t, math.floor(r * 0.55), BLACK)
            bb:paintRect(cx, cy - math.floor(t / 2), math.floor(r * 0.4), t, BLACK)
        end
    end }
end

-- Modules -------------------------------------------------------------------------------

local Spot = WidgetContainer:extend{}
function Spot:paintTo(bb, x, y)
    local s = self[1]:getSize()
    self.pos = Geom:new{ x = x, y = y, w = s.w, h = s.h }
    self[1]:paintTo(bb, x, y)
end

local M = {}

function M.clock_small(self)
    local now = os.date("*t")
    local date = string.format("%s, %d de %s", WEEKDAYS[now.wday], now.day, MONTHS[now.month])
    local left = VerticalGroup:new{ align = "left",
        text(os.date("%H:%M"), 34, { bold = true }),
        text(date, 15, { color = GRAY }),
    }
    local right = VerticalGroup:new{ align = "right" }
    local ok, cap = pcall(function() return Device:getPowerDevice():getCapacity() end)
    if ok and cap then table.insert(right, text("Bateria " .. cap .. "%", 14, { color = GRAY })) end
    local dim = Geom:new{ w = self.inner_w, h = left:getSize().h }
    self.clock_spot = Spot:new{ OverlapGroup:new{ dimen = dim:copy(),
        LeftContainer:new{ dimen = dim:copy(), left },
        RightContainer:new{ dimen = dim:copy(), right },
    } }
    return self.clock_spot
end

function M.clock_big(self, size, box)
    local now = os.date("*t")
    local date = string.format("%s, %d de %s", WEEKDAYS[now.wday], now.day, MONTHS[now.month])
    self.clock_spot = Spot:new{ fixed(self.inner_w, box or S(100), VerticalGroup:new{ align = "center",
        text(os.date("%H:%M"), size or 64, { font = "NotoSerif-Regular.ttf" }),
        text(date, 17, { color = GRAY }),
    }) }
    return self.clock_spot
end

function M.current(self)
    local b = self.current_book
    if not b then return nil end
    local d = Library.details(b)
    local ch = S(170)
    local cw = math.floor(ch / 1.5)
    local col_w = self.inner_w - cw - S(20)
    local meta = math.floor((b.percent or 0) * 100 + 0.5) .. "%"
    local left = Library.timeLeft(b)
    if left then meta = meta .. "  ·  " .. fmtDuration(left) .. " restantes" end
    local info = VerticalGroup:new{ align = "left",
        textbox(b.title, 20, col_w, 2, { font = "NotoSerif-Bold.ttf" }),
        vspan(S(4)),
        text(b.author, 15, { color = GRAY, max_width = col_w }),
        vspan(S(18)),
        progressBar(col_w, b.percent, math.max(4, S(4))),
        vspan(S(8)),
        text(meta, 14),
        vspan(S(4)),
        text(agoText(b.read_time) or "", 13, { color = GRAY }),
    }
    return VerticalGroup:new{ align = "left", label("Lendo agora"), vspan(S(10)),
        tap(HorizontalGroup:new{ align = "top", (cover(b, cw, ch)), hspan(S(20)), info },
            function() self:open(b) end) }
end

function M.current_hero(self, cover_h)
    local b = self.current_book
    if not b then
        return VerticalGroup:new{ align = "center", vspan(S(60)),
            text("Nenhum livro em andamento", 18, { color = GRAY }), vspan(S(16)),
            tap(FrameContainer:new{ bordersize = math.max(1, S(1)), color = BLACK, radius = S(8),
                padding = S(12), padding_left = S(24), padding_right = S(24), margin = 0,
                text("Abrir biblioteca", 16, { bold = true }) },
                function() self:nav("biblioteca") end),
            vspan(S(60)) }
    end
    local d = Library.details(b)
    local ch = cover_h or S(215)
    local cw = math.floor(ch / 1.5)
    local meta = math.floor((b.percent or 0) * 100 + 0.5) .. "% lido"
    local left = Library.timeLeft(b)
    if left then meta = meta .. "  ·  " .. fmtDuration(left) .. " restantes" end
    return tap(VerticalGroup:new{ align = "center",
        fixed(self.inner_w, ch, (cover(b, cw, ch))),
        vspan(S(14)),
        textbox(b.title, 20, self.inner_w, 2, { font = "NotoSerif-Bold.ttf", alignment = "center" }),
        text(b.author, 15, { color = GRAY }),
        vspan(S(12)),
        progressBar(S(240), b.percent, math.max(4, S(4))),
        vspan(S(8)),
        text(meta, 14, { color = GRAY }),
    }, function() self:open(b) end)
end

-- One discreet line: "17:43 · sábado, 31 de outubro"
function M.clock_line(self)
    local now = os.date("*t")
    local date = string.format("%s, %d de %s", WEEKDAYS[now.wday], now.day, MONTHS[now.month])
    self.clock_spot = Spot:new{ fixed(self.inner_w, S(34), HorizontalGroup:new{ align = "center",
        text(os.date("%H:%M"), 22, { bold = true }),
        text("   ·   " .. date, 15, { color = GRAY }),
    }, "left") }
    return self.clock_spot
end

function M.clock_mid(self) return M.clock_big(self, 50, S(80)) end
function M.current_hero_mid(self) return M.current_hero(self, S(165)) end

-- The other books in progress, as a row of small covers with their progress.
function M.also_reading(self)
    local list = {}
    for _, b in ipairs(self.books) do
        if b ~= self.current_book and b.status == "reading" then table.insert(list, b) end
        if #list == 5 then break end
    end
    if #list == 0 then return nil end
    local gap, h = S(16), S(118)
    local w = math.floor(h / 1.5)
    local hg = HorizontalGroup:new{ align = "top" }
    for i, b in ipairs(list) do
        if i > 1 then table.insert(hg, hspan(gap)) end
        table.insert(hg, tap(VerticalGroup:new{ align = "left",
            (cover(b, w, h)), vspan(S(6)),
            progressBar(w, b.percent),
            vspan(S(4)),
            text(math.floor((b.percent or 0) * 100 + 0.5) .. "%", 12, { color = GRAY }),
        }, function() self:open(b) end))
    end
    return VerticalGroup:new{ align = "left", label("Também lendo  ·  " .. #list), vspan(S(10)), hg }
end

local function coverRow(self, list, n, title)
    if #list == 0 then return nil end
    local gap = S(14)
    local w = math.floor((self.inner_w - gap * (n - 1)) / n)
    local h = math.floor(w * 1.5)
    local hg = HorizontalGroup:new{ align = "top" }
    for i = 1, math.min(n, #list) do
        local b = list[i]
        if i > 1 then table.insert(hg, hspan(gap)) end
        table.insert(hg, tap(VerticalGroup:new{ align = "left", (cover(b, w, h)), vspan(S(6)),
            b.status == "reading" and progressBar(w, b.percent) or vspan(math.max(3, S(3))) },
            function() self:open(b) end))
    end
    return VerticalGroup:new{ align = "left", label(title), vspan(S(10)), hg }
end

function M.recent(self)
    local list = {}
    for _, b in ipairs(self.books) do
        if b ~= self.current_book and b.read_time then table.insert(list, b) end
    end
    return coverRow(self, list, 5, "Recentes")
end

-- Overlapping covers ("estante")
local Deck = InputContainer:extend{ books = nil, cw = 0, ch = 0, step = 0, on_open = nil }
function Deck:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.cw + self.step * (#self.books - 1), h = self.ch }
    self.ges_events = { TapDeck = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    self.covers = {}
    for i, b in ipairs(self.books) do self.covers[i] = (cover(b, self.cw, self.ch)) end
end
function Deck:getSize() return Geom:new{ w = self.dimen.w, h = self.dimen.h } end
function Deck:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    -- rightmost first, so each cover sits on top of the next one
    for i = #self.covers, 1, -1 do
        local cx = x + (i - 1) * self.step
        bb:paintRect(cx, y, self.cw + S(5), self.ch, WHITE)
        self.covers[i]:paintTo(bb, cx, y)
    end
end
function Deck:onTapDeck(_, ges)
    local rel = ges.pos.x - self.dimen.x
    local i = rel < self.cw and 1 or math.floor((rel - self.cw) / self.step) + 2
    i = math.max(1, math.min(#self.books, i))
    self.on_open(self.books[i])
    return true
end

function M.deck(self)
    local list = {}
    for _, b in ipairs(self.books) do
        if b.status == "new" then table.insert(list, b) end
        if #list == 7 then break end
    end
    if #list == 0 then return nil end
    local ch = S(190)
    local cw = math.floor(ch / 1.5)
    local step = math.floor((self.inner_w - cw) / math.max(1, #list - 1))
    step = math.min(step, cw + S(14))
    return VerticalGroup:new{ align = "left",
        label("Para ler a seguir  ·  " .. #list), vspan(S(10)),
        Deck:new{ books = list, cw = cw, ch = ch, step = step, on_open = function(b) self:open(b) end },
    }
end

-- Shelf of the other books in progress (history only, so it's fast).
function M.reading_deck(self)
    local list = {}
    for _, b in ipairs(self.books) do
        if b ~= self.current_book and b.status == "reading" then table.insert(list, b) end
        if #list == 7 then break end
    end
    if #list == 0 then return nil end
    local ch = S(190)
    local cw = math.floor(ch / 1.5)
    local step = #list > 1 and math.floor((self.inner_w - cw) / (#list - 1)) or cw
    step = math.min(step, cw + S(14))
    return VerticalGroup:new{ align = "left",
        label("Também lendo  ·  " .. #list), vspan(S(10)),
        Deck:new{ books = list, cw = cw, ch = ch, step = step, on_open = function(b) self:open(b) end },
    }
end

local quote_cache = {}
function M.quote(self)
    local q, src
    local today = os.date("%Y-%m-%d")
    if quote_cache.day == today and quote_cache.q then
        q, src = quote_cache.q, quote_cache.src
        return M.quoteCard(self, q, src)
    end
    local pool = {}
    for _, b in ipairs(self.books) do
        if b.read_time then
            local d = Library.details(b)
            for _, a in ipairs(d.annotations or {}) do
                if a.text and #a.text > 20 and #a.text < 260 then
                    table.insert(pool, { a.text, b.title .. "  ·  seu destaque" })
                end
            end
        end
    end
    if #pool == 0 then pool = QUOTES end
    local pick = pool[(os.date("*t").yday % #pool) + 1]
    q, src = pick[1], pick[2]
    quote_cache.day, quote_cache.q, quote_cache.src = today, q, src
    return M.quoteCard(self, q, src)
end

function M.quoteCard(self, q, src)
    local inner = self.inner_w - 2 * S(18)
    return VerticalGroup:new{ align = "left", label("Citação do dia"), vspan(S(10)),
        FrameContainer:new{ bordersize = math.max(1, S(1)), color = LIGHT, radius = S(10),
            padding = S(18), margin = 0,
            VerticalGroup:new{ align = "left",
                textbox("“" .. q .. "”", 19, inner, 5, { font = "NotoSerif-Italic.ttf" }),
                vspan(S(10)),
                fixed(inner, S(20), text("— " .. src, 13, { color = GRAY, max_width = inner }), "right"),
            } } }
end

function M.goal(self)
    local year = os.date("%Y")
    local target = G_reader_settings:readSetting("kindle_home_goal") or 12
    local done = 0
    for _, b in ipairs(self.books) do
        if b.status == "complete" then
            local d = Library.details(b)
            if not d.finished_on or d.finished_on:sub(1, 4) == year then done = done + 1 end
        end
    end
    local dim = Geom:new{ w = self.inner_w, h = S(30) }
    return VerticalGroup:new{ align = "left", label("Meta de " .. year), vspan(S(8)),
        OverlapGroup:new{ dimen = dim:copy(),
            LeftContainer:new{ dimen = dim:copy(), text(done .. " de " .. target .. " livros", 20, { bold = true }) },
            RightContainer:new{ dimen = dim:copy(),
                text(math.floor(done / target * 100 + 0.5) .. "%", 15, { color = GRAY }) } },
        vspan(S(8)),
        progressBar(self.inner_w, done / target, math.max(6, S(6))),
    }
end

local function daysMap(self)
    if not self._daily then self._daily = Stats.daily(200) end
    return self._daily
end

function M.stats(self)
    local daily = daysMap(self)
    local function day(offset) return os.date("%Y-%m-%d", os.time() - offset * 86400) end
    local today = daily[day(0)] or 0
    local week = 0
    for i = 0, 6 do week = week + (daily[day(i)] or 0) end
    local streak, i = 0, (daily[day(0)] and 0 or 1)
    while daily[day(i)] do streak = streak + 1; i = i + 1 end
    local cards = {
        { fmtDuration(today), "hoje" },
        { fmtDuration(week), "últimos 7 dias" },
        { streak .. (streak == 1 and " dia" or " dias"), "sequência" },
    }
    local gap = S(12)
    local w = math.floor((self.inner_w - 2 * gap) / 3)
    local hg = HorizontalGroup:new{}
    for k, c in ipairs(cards) do
        if k > 1 then table.insert(hg, hspan(gap)) end
        local bw = math.max(1, S(1))
        table.insert(hg, FrameContainer:new{ bordersize = bw, color = LIGHT, radius = S(10), padding = 0, margin = 0,
            fixed(w - 2 * bw, S(78), VerticalGroup:new{ align = "center",
                text(c[1], 21, { bold = true }), vspan(S(2)), text(c[2], 13, { color = GRAY }) }) })
    end
    return VerticalGroup:new{ align = "left", label("Leitura"), vspan(S(10)), hg }
end

function M.heatmap(self)
    local daily = daysMap(self)
    local weeks, gap = 26, math.max(2, S(3))
    local cell = math.floor((self.inner_w - (weeks - 1) * gap) / weeks)
    local levels = { LIGHT, Blitbuffer.COLOR_GRAY_9, Blitbuffer.COLOR_GRAY_5, BLACK }
    local now = os.date("*t")
    local today0 = os.time{ year = now.year, month = now.month, day = now.day, hour = 12 }
    local start = today0 - ((weeks - 1) * 7 + (now.wday - 1)) * 86400
    local grid = Paint:new{ width = weeks * (cell + gap) - gap, height = 7 * (cell + gap) - gap,
        draw = function(bb, x, y)
            for wk = 0, weeks - 1 do
                for wd = 0, 6 do
                    local t = start + (wk * 7 + wd) * 86400
                    if t <= today0 then
                        local sec = daily[os.date("%Y-%m-%d", t)] or 0
                        local px, py = x + wk * (cell + gap), y + wd * (cell + gap)
                        if sec <= 0 then
                            bb:paintBorder(px, py, cell, cell, 1, LIGHT)
                        else
                            local lvl = sec < 900 and 1 or (sec < 1800 and 2 or (sec < 3600 and 3 or 4))
                            bb:paintRect(px, py, cell, cell, levels[lvl])
                        end
                    end
                end
            end
        end }
    local legend = HorizontalGroup:new{ align = "center", text("menos ", 12, { color = GRAY }) }
    for _, c in ipairs({ "empty", 1, 2, 3, 4 }) do
        local col = levels[c]
        table.insert(legend, Paint:new{ width = S(12), height = S(12), draw = function(bb, x, y, w, h)
            if c == "empty" then bb:paintBorder(x, y, w, h, 1, LIGHT) else bb:paintRect(x, y, w, h, col) end
        end })
        table.insert(legend, hspan(S(3)))
    end
    table.insert(legend, text(" mais", 12, { color = GRAY }))
    return VerticalGroup:new{ align = "left", label("Atividade  ·  últimos 6 meses"), vspan(S(10)), grid,
        vspan(S(8)), fixed(self.inner_w, S(16), legend, "right") }
end

function M.actions(self)
    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    local wifi_on = ok_nm and NetworkMgr:isWifiOn()
    local function run(action)
        return function()
            UIManager:nextTick(function()
                require("dispatcher"):execute({ [action] = true })
                UIManager:scheduleIn(1, function() if not self.closed then self:rebuild(); self:refresh("ui") end end)
            end)
        end
    end
    local items = {
        { IconWidget:new{ icon = wifi_on and "wifi.open.100" or "wifi.open.0", width = S(26), height = S(26) },
            wifi_on and "Wi-Fi ligado" or "Wi-Fi", run("toggle_wifi") },
        { glyph("sun", S(28)), "Luz", run("show_frontlight_dialog") },
        { IconWidget:new{ icon = "appbar.contrast", width = S(26), height = S(26) }, "Noturno", run("night_mode") },
        { glyph("clock", S(28)), "Histórico", run("history") },
        { IconWidget:new{ icon = "star.empty", width = S(26), height = S(26) }, "Favoritos", run("favorites") },
        { glyph("moon", S(26)), "Repouso", run("suspend") },
    }
    local w = math.floor(self.inner_w / #items)
    local hg = HorizontalGroup:new{}
    local d = S(54)
    for _, it in ipairs(items) do
        local bw = math.max(1, S(1))
        local btn = FrameContainer:new{ bordersize = bw, color = MID, radius = math.floor(d / 2),
            padding = 0, margin = 0, fixed(d - 2 * bw, d - 2 * bw, it[1]) }
        table.insert(hg, tap(fixed(w, d + S(26), VerticalGroup:new{ align = "center",
            btn, vspan(S(6)), text(it[2], 12, { color = GRAY }) }), it[3]))
    end
    return VerticalGroup:new{ align = "left", label("Ações rápidas"), vspan(S(10)), hg }
end

function Home:viewModules(avail_h, preset)
    self.current_book = nil
    for _, b in ipairs(self.books) do
        if b.read_time and b.status ~= "complete" then self.current_book = b break end
    end
    local vg = VerticalGroup:new{ align = "left" }
    local used = 0
    local gap = S(26)
    for _, name in ipairs(PRESETS[preset]) do
        local ok, w = pcall(M[name], self)
        if not ok then logger.warn("kindle-home module", name, w) w = nil end
        if w then
            local h = w:getSize().h
            if used + h > avail_h then break end
            table.insert(vg, w)
            table.insert(vg, vspan(gap))
            used = used + h + gap
        end
    end
    return vg
end

-- Style "inicio" -------------------------------------------------------------------

function Home:viewInicio(avail_h)
    local books = self.books
    local current
    for _, b in ipairs(books) do
        if b.read_time and b.status ~= "complete" then current = b break end
    end
    local vg = VerticalGroup:new{ align = "left" }
    local used = 0
    local function add(w) table.insert(vg, w); used = used + w:getSize().h end

    if current then
        add(self:sectionTitle("Continuar lendo"))
        local ch = S(180)
        local cw = math.floor(ch / 1.5)
        local col_w = self.inner_w - cw - S(20)
        local info = VerticalGroup:new{ align = "left",
            textbox(current.title, 21, col_w, 3, { font = "NotoSerif-Bold.ttf" }),
            vspan(S(6)),
            textbox(current.author, 15, col_w, 2, { color = GRAY }),
            vspan(S(22)),
            progressBar(col_w, current.percent, math.max(4, S(4))),
            vspan(S(8)),
            text(math.floor((current.percent or 0) * 100 + 0.5) .. "% lido", 14, { color = GRAY }),
        }
        add(tap(HorizontalGroup:new{ align = "top", (cover(current, cw, ch)), hspan(S(20)), info },
            function() self:open(current) end))
        add(vspan(S(14)))
    end

    local function row(title, list, n)
        if #list == 0 then return end
        local gap = S(14)
        local w = math.floor((self.inner_w - gap * (n - 1)) / n)
        local h = math.floor(w * 1.5)
        if used + S(36) + h + S(14) > avail_h then return end
        add(self:sectionTitle(title))
        local hg = HorizontalGroup:new{ align = "top" }
        for i = 1, math.min(n, #list) do
            local b = list[i]
            if i > 1 then table.insert(hg, hspan(gap)) end
            local item = VerticalGroup:new{ align = "left", (cover(b, w, h)), vspan(S(6)),
                b.status == "reading" and progressBar(w, b.percent) or vspan(math.max(3, S(3))) }
            table.insert(hg, tap(item, function() self:open(b) end))
        end
        add(hg)
        add(vspan(S(12)))
    end

    local recent, unread = {}, {}
    for _, b in ipairs(books) do
        if b ~= current then
            if b.read_time then table.insert(recent, b)
            elseif b.status == "new" then table.insert(unread, b) end
        end
    end
    row("Recentes", recent, 5)
    row("Ainda não lidos", unread, 5)
    return vg
end

-- Styles "grade" and "lista" ---------------------------------------------------------

local FILTERS = { { "todos", "Todos" }, { "lendo", "Lendo" }, { "novos", "Não lidos" }, { "lidos", "Lidos" } }

function Home:filtered()
    local out = {}
    for _, b in ipairs(self.books) do
        local f = self.filter
        if f == "todos" or (f == "lendo" and b.status == "reading") or (f == "novos" and b.status == "new")
            or (f == "lidos" and b.status == "complete") then
            table.insert(out, b)
        end
    end
    return out
end

function Home:filterChips()
    local hg = HorizontalGroup:new{}
    for i, f in ipairs(FILTERS) do
        local active = f[1] == self.filter
        local label = text(f[2], 14, { bold = active, color = active and WHITE or BLACK })
        local chip = FrameContainer:new{
            bordersize = math.max(1, S(1)), color = active and BLACK or MID,
            background = active and BLACK or WHITE, radius = S(17),
            padding = 0, padding_left = S(14), padding_right = S(14), margin = 0,
            fixed(label:getSize().w, S(32), label),
        }
        if i > 1 then table.insert(hg, hspan(S(8))) end
        table.insert(hg, tap(chip, function()
            self.filter = f[1]; self.page = 1; self:rebuild(); self:refresh("ui")
        end))
    end
    return VerticalGroup:new{ align = "left", hg, vspan(S(14)) }
end

function Home:pager(pages, w)
    local dim = Geom:new{ w = w, h = S(44) }
    local g = OverlapGroup:new{ dimen = dim:copy(),
        CenterContainer:new{ dimen = dim:copy(), text(self.page .. " de " .. pages, 14, { color = GRAY }) } }
    if self.page > 1 then
        table.insert(g, LeftContainer:new{ dimen = dim:copy(), tap(text("  ‹  ", 26), function() self:turn(-1) end) })
    end
    if self.page < pages then
        table.insert(g, RightContainer:new{ dimen = dim:copy(), tap(text("  ›  ", 26), function() self:turn(1) end) })
    end
    return g
end

function Home:viewGrade(avail_h)
    local chips = self:filterChips()
    local list = self:filtered()
    local cols, rows, gap = 3, 2, S(16)
    local col_w = math.floor((self.inner_w - gap * (cols - 1)) / cols)
    local extra = S(8) + S(22) + S(6) + S(14) + S(16)
    local h = math.floor((avail_h - chips:getSize().h - S(44)) / rows) - extra
    local w = math.min(col_w, math.floor(h / 1.42))
    h = math.floor(w * 1.42)
    local per = rows * cols
    local pages = math.max(1, math.ceil(#list / per))
    self.page = math.min(self.page, pages)
    self.pages = pages
    local vg = VerticalGroup:new{ align = "left", chips }
    local first = (self.page - 1) * per + 1
    for r = 0, rows - 1 do
        local hg = HorizontalGroup:new{ align = "top" }
        for c = 0, cols - 1 do
            local b = list[first + r * cols + c]
            if c > 0 then table.insert(hg, hspan(gap)) end
            if not b then table.insert(hg, hspan(col_w)) end
            if b then
                local status
                if b.status == "complete" then status = text("Lido", 12, { color = GRAY })
                elseif b.status == "new" then status = text("Novo", 12, { bold = true })
                else status = progressBar(w, b.percent) end
                table.insert(hg, tap(VerticalGroup:new{ align = "center",
                    fixed(col_w, h, (cover(b, w, h))), vspan(S(8)),
                    text(b.title, 13, { max_width = w }),
                    vspan(S(6)), fixed(w, S(14), status, "left"),
                }, function() self:open(b) end))
            end
        end
        table.insert(vg, hg)
        table.insert(vg, vspan(S(16)))
    end
    local body_h = vg:getSize().h
    vg:resetLayout()
    table.insert(vg, vspan(math.max(0, avail_h - body_h - S(44))))
    table.insert(vg, self:pager(pages, self.inner_w))
    return vg
end

function Home:viewLista(avail_h)
    local chips = self:filterChips()
    local list = self:filtered()
    local row_h = S(112)
    local per = math.max(1, math.floor((avail_h - chips:getSize().h - S(44)) / row_h))
    local pages = math.max(1, math.ceil(#list / per))
    self.page = math.min(self.page, pages)
    self.pages = pages
    local vg = VerticalGroup:new{ align = "left", chips,
        LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = 1 }, background = LIGHT } }
    local first = (self.page - 1) * per + 1
    local cw, ch = S(62), S(90)
    local right_w = S(70)
    local col_w = self.inner_w - cw - S(16) - right_w
    for i = first, math.min(#list, first + per - 1) do
        local b = list[i]
        local status
        if b.status == "complete" then status = text("Lido ✓", 13, { color = GRAY })
        elseif b.status == "new" then status = text("Novo", 13, { bold = true })
        else status = text(math.floor(b.percent * 100 + 0.5) .. "%", 15, { bold = true }) end
        local info = VerticalGroup:new{ align = "left",
            textbox(b.title, 17, col_w, 2, { font = "NotoSerif-Bold.ttf" }),
            vspan(S(4)),
            text(b.author, 14, { color = GRAY, max_width = col_w }),
        }
        if b.status == "reading" then
            table.insert(info, vspan(S(10)))
            table.insert(info, progressBar(math.floor(col_w * 0.8), b.percent))
        end
        local row = HorizontalGroup:new{ align = "center",
            (cover(b, cw, ch)), hspan(S(16)),
            fixed(col_w, row_h - 1, info, "left"),
            fixed(right_w, row_h - 1, status, "right"),
        }
        table.insert(vg, tap(VerticalGroup:new{ row,
            LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = 1 }, background = LIGHT } },
            function() self:open(b) end))
    end
    local body_h = vg:getSize().h
    vg:resetLayout()
    table.insert(vg, vspan(math.max(0, avail_h - body_h - S(44))))
    table.insert(vg, self:pager(pages, self.inner_w))
    return vg
end

-- Assembly ---------------------------------------------------------------------------

function Home:rebuild()
    local title = self.view == "inicio" and "Início" or "Biblioteca"
    local top = self:topBar(title)
    local nav = self:navBar()
    local avail_h = self.sh - top:getSize().h - nav:getSize().h - S(10)
    local body
    if self.view == "inicio" then
        body = PRESETS[style()] and self:viewModules(avail_h, style()) or self:viewInicio(avail_h)
    elseif style() == "lista" then
        body = self:viewLista(avail_h)
    else
        body = self:viewGrade(avail_h)
    end
    self.top, self.nav_bar = top, nav
    self.body = HorizontalGroup:new{ hspan(self.pad), body }
end

function Home:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.sw, self.sh, WHITE)
    self.top:paintTo(bb, 0, 0)
    self.body:paintTo(bb, 0, self.top:getSize().h + S(4))
    self.nav_bar:paintTo(bb, 0, self.sh - self.nav_bar:getSize().h)
end

-- Gestures go to the three parts by hand (they're painted at fixed positions).
function Home:handleEvent(ev)
    if ev.handler == "onGesture" then
        for _, part in ipairs({ self.top, self.body, self.nav_bar }) do
            if part and part:handleEvent(ev) then return true end
        end
    end
    return InputContainer.handleEvent(self, ev)
end

function Home:refresh(mode)
    UIManager:setDirty(self, mode or "ui")
end

function Home:turn(d)
    local p = self.page + d
    if p >= 1 and p <= (self.pages or 1) then
        self.page = p
        self:rebuild()
        self:refresh("ui")
    end
end

function Home:onSwipeHome(_, ges)
    if self.view ~= "inicio" then
        if ges.direction == "west" then self:turn(1) elseif ges.direction == "east" then self:turn(-1) end
    end
    return true
end
local STYLES = {
    { "estante_relogio", "Estante com relógio" }, { "minimal_estante", "Minimalista + estante" }, { "minimal", "Minimalista" }, { "painel", "Painel" }, { "dados", "Dados" }, { "estante", "Estante" },
    { "inicio", "Início Kindle" }, { "grade", "Só biblioteca em grade" }, { "lista", "Só biblioteca em lista" },
}

-- Hold the title to pick another style.
function Home:onHoldHome(_, ges)
    if ges.pos.y > S(64) then return true end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}
    for _, st in ipairs(STYLES) do
        table.insert(buttons, { {
            text = (st[1] == style() and "✓  " or "") .. st[2],
            callback = function()
                UIManager:close(dialog)
                G_reader_settings:saveSetting("kindle_home_style", st[1])
                self.view = (st[1] == "grade" or st[1] == "lista") and "biblioteca" or "inicio"
                self.page = 1
                self:reload()
                self:refresh("flashui")
            end,
        } })
    end
    dialog = ButtonDialog:new{ title = "Estilo da tela inicial", buttons = buttons }
    UIManager:show(dialog)
    return true
end
function Home:onTapHome() return true end

function Home:close()
    if self.closed then return end
    self.closed = true
    if self.tick then UIManager:unschedule(self.tick) end
    UIManager:close(self, "flashui")
    FileManager._kindle_home = nil
end

function Home:onClose() self:close() return true end

local function showHome()
    if FileManager._kindle_home then return end
    local ok, home = pcall(Home.new, Home, {})
    if not ok then logger.warn("kindle-home:", home) return end
    FileManager._kindle_home = home
    UIManager:show(home, "flashui")
end

-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------

local orig_init = FileManager.init
FileManager.init = function(self, ...)
    orig_init(self, ...)
    UIManager:nextTick(function()
        if FileManager.instance == self then showHome() end
    end)
end

-- House icon in the file browser -> back to this screen.
local orig_home = FileManager.onHome
FileManager.onHome = function(self, ...)
    local r = orig_home(self, ...)
    UIManager:nextTick(showHome)
    return r
end

local orig_showingReader = FileManager.onShowingReader
FileManager.onShowingReader = function(self, ...)
    if FileManager._kindle_home then FileManager._kindle_home:close() end
    return orig_showingReader(self, ...)
end
