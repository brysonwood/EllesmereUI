if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_Sparkles.lua  (WoW Forever only)
--  Loot Sparkles: whichever ore vein, herb, chest, quest object, lootable body
--  or fishing bobber the client's interact targeting points at gets a sparkle
--  in the colour picked for its kind, so it is seen before it is in reach.
--
--  Interact targeting is the game's own soft target, the "softinteract" unit:
--  the client marks one interactable at a time and pins its interact icon to
--  that unit's nameplate (Blizzard's NamePlateDriverMixin, and the plate's
--  SoftTargetFrame). The sparkle is a frame parented to that nameplate, so
--  the client does the following and the hiding, and every motion is an
--  AnimationGroup: no Lua runs per frame and no timer polls.
--
--  A kind is read from the object, never from tooltip text a language or a
--  player can change: the bobber by its game object ID, chests by the object
--  IDs the loot window taught, herbs and ore by the node names Gathering
--  Skill already keeps for every client language, quest objects by the quest
--  log, and a body by being dead.
--
--  The client's soft-target settings are held only while the feature is on
--  (EllesmereUI.HoldCVar keeps what the player had, ReleaseCVar gives it
--  back), written out of combat only and written again after a graphics
--  preset, which resets them.
-------------------------------------------------------------------------------
local _, module = ...

local OWNER = "EllesmereUIForeverEssentials"
-- The unit the client's interact targeting points at, and the plate it marks.
local TARGET = "softinteract"
local GLOW = "Interface\\AddOns\\EllesmereUI\\media\\unlock-flash.png"
local STREAK = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"
local STAR = "Interface\\Cooldown\\star4"  -- Blizzard's four-point twinkle
local BOBBER = 35591

-- The sparkle's box, and how far below the plate's centre it sits: a plate
-- stands over its unit, a chest or a node has the sparkle over its lid.
local SIZE = 64
local OFFSET_Y = -26

-- The kinds and their starting colour, and the four styles. Every kind
-- starts in the house gold, the colour of the game's loot sparkle (1, 0.82,
-- 0.30 as elsewhere in the suite); a kind's own swatch overrides it.
--
-- A style is a list of layers over one frame: a texture, its size and place
-- on the frame, and the loop that moves it (alpha/scale = from, to, seconds;
-- rise = pixels up over the same seconds; turn = the texture's own angle;
-- delay = seconds before the loop starts; loop = BOUNCE unless given).
local GOLD = { 1.00, 0.82, 0.30 }
local COLORS = {
    ore    = GOLD,
    herb   = GOLD,
    chest  = GOLD,
    quest  = GOLD,
    corpse = GOLD,
    bobber = GOLD,
}
local STYLES = {
    glow = {
        { tex = GLOW, w = 62, h = 62, alpha = { 0.22, 0.58, 1.2 } },
    },
    beam = {
        { tex = GLOW, w = 38, h = 38, y = -18, alpha = { 0.28, 0.58, 1.0 } },
        { tex = STREAK, w = 10, h = 76, y = 22, alpha = { 0.85, 0, 1.3 }, rise = 64, loop = "REPEAT" },
    },
    flare = {
        { tex = GLOW, w = 54, h = 54, alpha = { 0.18, 0.42, 1.1 } },
        { tex = STAR, w = 42, h = 42, scale = { 0.55, 1.15, 0.9 }, alpha = { 0.9, 0.15, 0.9 } },
    },
    sparkle = {
        { tex = STAR, w = 26, h = 26, alpha = { 0.85, 0.25, 0.7 } },
        { tex = STAR, w = 15, h = 15, x = -14, y = 13, alpha = { 0, 0.9, 0.9 }, delay = 0.35, turn = 0.785 },
        { tex = STAR, w = 13, h = 13, x = 16, y = -11, alpha = { 0, 0.8, 1.1 }, delay = 0.7, turn = 0.785 },
    },
}
local STYLE_NAMES = { glow = "Glow", beam = "Beam", flare = "Flare", sparkle = "Sparkle" }
local STYLE_ORDER = { "glow", "beam", "flare", "sparkle" }

-- Settings live in EllesmereUIDB.sparkles; unset keys read these: the switch,
-- the range in yards, the style, one switch per kind, a kind's colour in
-- colors[kind] = { r, g, b }, and the container object IDs the loot window
-- taught in containers, which survive a reset so chests stay known.
local F = module.Feature("sparkles", {
    enabled = false, range = 15, style = "glow", hideGameSparkle = false,
    ore = true, herb = true, chest = true, quest = true, corpse = true, bobber = true,
})

local GS = EllesmereUI._GatherSkill  -- the node names Gathering Skill keeps

-------------------------------------------------------------------------------
--  Following this character's professions
-------------------------------------------------------------------------------
-- The ore and herb kinds can follow what the character can actually gather.
-- The switch is this character's own, on its roster entry (an account-wide
-- one would have an enchanter sparkle ore), and it never writes the kind
-- switches: it overrides them while on, so turning it off gives the player's
-- own picks back untouched.
local AUTO_SKILL = { ore = 186, herb = 182 }  -- Mining, Herbalism
local AUTO_ORDER = { "ore", "herb" }
local GATHER_SPELL = { ore = 2575, herb = 2366 }  -- their profession spells, for the names

local function AutoRead()
    local c = EllesmereUI.CharData("lootSparkles")
    return c ~= nil and c.auto == true
end

local function AutoWrite(on)
    local c = EllesmereUI.CharData("lootSparkles", on)
    if on then
        if c then c.auto = true end
        return
    end
    if not c then return end
    c.auto = nil
    -- Nothing else of ours is per character: an empty table is not kept.
    if next(c) == nil then
        local entry = EllesmereUI.CharEntry(false)
        if entry then entry.lootSparkles = nil end
    end
end

-- Whether this character has the skill line at all (Gathering Skill already
-- reads the professions this way for its tooltips).
local function HasSkill(line)
    return GS ~= nil and GS.Skill ~= nil and GS.Skill(line) ~= nil
end

-- Whether a kind sparkles now: an ore or herb kind follows the professions
-- while that is on, every other kind reads its own switch.
local function KindOn(kind)
    local line = AUTO_SKILL[kind]
    if line and AutoRead() then return HasSkill(line) end
    return F.Get(kind) == true
end

-- What this character can gather, in the client's own words ("Mining 75,
-- Herbalism 120"), for the page's note beside the switch.
local function GatheringText()
    if not (GS and GS.Skill) then return "" end
    local parts = {}
    for i = 1, #AUTO_ORDER do
        local kind = AUTO_ORDER[i]
        local rank = GS.Skill(AUTO_SKILL[kind])
        if rank then
            local name = C_Spell.GetSpellName(GATHER_SPELL[kind]) or kind
            parts[#parts + 1] = name .. " " .. rank
        end
    end
    return table.concat(parts, ", ")
end

local ev = CreateFrame("Frame")      -- every event; inert while the feature is off
local built = {}                     -- style -> { frame = , layers = { { group, texture } } }
local onPlate                        -- the box on screen, while one is shown
local kindGuid, kindValue            -- the target last classified, and its kind

-------------------------------------------------------------------------------
--  What the target is
-------------------------------------------------------------------------------
-- A kind's colour: the player's own, or the one it starts with.
local function Colour(kind)
    local c = F.Read().colors
    c = c and c[kind]
    if c and c.r then return c.r, c.g, c.b end
    c = COLORS[kind]
    if not c then return 1, 1, 1 end
    return c[1], c[2], c[3]
end

-- Whether the quest log ties this unit to a quest the player is on.
local function QuestRelated(unit)
    local Q = C_QuestLog
    if not (Q and Q.UnitIsRelatedToActiveQuest) then return false end
    local ok, related = pcall(Q.UnitIsRelatedToActiveQuest, unit)
    return ok and not issecretvalue(related) and related == true
end

local function IsWorldObject(unit)
    local isObject = UnitIsGameObject(unit)
    return not issecretvalue(isObject) and isObject == true
end

-- The kind of the unit, or nil for something the sparkles leave alone.
local function Classify(unit, guid)
    local id = module.ObjectID(guid)
    if id == BOBBER then return "bobber" end
    local learned = F.Read().containers
    if id and learned and learned[id] then return "chest" end
    if IsWorldObject(unit) then
        local name = UnitName(unit)
        if name and not issecretvalue(name) and GS and GS.NodeKind then
            local node = GS.NodeKind(name)
            if node then return node end
        end
        if QuestRelated(unit) then return "quest" end
        return nil
    end
    -- A creature is worth a sparkle once it is a body to loot. A player's
    -- corpse is not, and neither is the player's own.
    local dead = UnitIsDead(unit)
    if not issecretvalue(dead) and dead == true and not UnitIsPlayer(unit) then return "corpse" end
end

-- The target's kind, read once per target: a plate comes and goes for every
-- unit around while the same object stands in front of the player.
local function TargetKind()
    local guid = UnitGUID(TARGET)
    if issecretvalue(guid) then guid = nil end
    if guid and guid == kindGuid then return kindValue end
    kindGuid, kindValue = guid, Classify(TARGET, guid)
    return kindValue
end

-- The plate the interact target is marked on: its own unit's, or any plate
-- the client hands out for the same unit.
local function TargetPlate()
    local C = C_NamePlate
    if not (C and C.GetNamePlateForUnit) then return nil end
    local plate = C.GetNamePlateForUnit(TARGET)
    if plate then return plate end
    if not C.GetNamePlates then return nil end
    local plates = C.GetNamePlates()
    for i = 1, #plates do
        local unit = plates[i].namePlateUnitToken
        if unit and UnitIsUnit(unit, TARGET) then return plates[i] end
    end
end

-- A game object the loot window named is a container, whatever the client
-- calls it: a chest, a crate, a barrel. Learning its ID is what lets the
-- next one of its kind sparkle before it is opened.
local function LearnContainers()
    if not (GetNumLootItems and GetLootSourceInfo) then return end
    local cfg
    for slot = 1, GetNumLootItems() or 0 do
        local id = module.ObjectID(GetLootSourceInfo(slot))
        if id and id ~= BOBBER then
            cfg = cfg or F.Cfg()
            cfg.containers = cfg.containers or {}
            cfg.containers[id] = true
        end
    end
    if cfg then kindGuid = nil end  -- what was last read may now be a chest
end

-------------------------------------------------------------------------------
--  The sparkle
-------------------------------------------------------------------------------
-- One layer: a texture on a little frame, moved by a looping group.
local function BuildLayer(host, spec)
    local f = CreateFrame("Frame", nil, host)
    f:SetSize(spec.w, spec.h)
    f:SetPoint("CENTER", host, "CENTER", spec.x or 0, spec.y or 0)
    local t = f:CreateTexture(nil, "ARTWORK", nil, 5)
    t:SetAllPoints(f)
    t:SetTexture(spec.tex)
    t:SetBlendMode("ADD")
    if spec.turn then t:SetRotation(spec.turn) end

    local g = f:CreateAnimationGroup()
    g:SetLooping(spec.loop or "BOUNCE")
    local delay = spec.delay or 0
    local a = spec.alpha
    if a then
        f:SetAlpha(a[1])
        local an = g:CreateAnimation("Alpha")
        an:SetFromAlpha(a[1])
        an:SetToAlpha(a[2])
        an:SetDuration(a[3])
        an:SetSmoothing("IN_OUT")
        an:SetStartDelay(delay)
    end
    local s = spec.scale
    if s then
        local an = g:CreateAnimation("Scale")
        an:SetScaleFrom(s[1], s[1])
        an:SetScaleTo(s[2], s[2])
        an:SetDuration(s[3])
        an:SetSmoothing("IN_OUT")
        an:SetStartDelay(delay)
    end
    if spec.rise then
        local an = g:CreateAnimation("Translation")
        an:SetOffset(0, spec.rise)
        an:SetDuration(a and a[3] or 1)
        an:SetSmoothing("OUT")
        an:SetStartDelay(delay)
    end
    return { frame = f, group = g, texture = t }
end

-- A style's box, built on first use and kept: switching styles back and
-- forth costs nothing after the first time.
local function BoxFor(style)
    local box = built[style]
    if box then return box end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(SIZE, SIZE)
    host:EnableMouse(false)
    -- The plate the box hangs on shrinks with distance; the sparkle is a
    -- world object at a fixed size, so it is not drawn at the plate's scale.
    if host.SetIgnoreParentScale then host:SetIgnoreParentScale(true) end
    host:Hide()
    box = { frame = host, layers = {} }
    local specs = STYLES[style] or STYLES.glow
    for i = 1, #specs do box.layers[i] = BuildLayer(host, specs[i]) end
    built[style] = box
    return box
end

local function StopBox(box)
    for i = 1, #box.layers do box.layers[i].group:Stop() end
    box.frame:Hide()
    box.playing = false
end

local function HideSparkle()
    if onPlate then StopBox(onPlate) end
    onPlate = nil
end

local function ShowSparkle(plate, style, r, g, b)
    local box = BoxFor(style)
    if onPlate and onPlate ~= box then StopBox(onPlate) end
    if box.frame:GetParent() ~= plate then box.frame:SetParent(plate) end
    box.frame:ClearAllPoints()
    box.frame:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
    for i = 1, #box.layers do box.layers[i].texture:SetVertexColor(r, g, b) end
    box.frame:Show()
    if not box.playing then
        box.playing = true
        for i = 1, #box.layers do box.layers[i].group:Play() end
    end
    onPlate = box
end

-- Reads the target and draws, moves or takes away the sparkle.
local function Evaluate()
    if not F.Enabled() then return end
    local kind = TargetKind()
    if not (kind and KindOn(kind)) then HideSparkle(); return end
    local plate = TargetPlate()
    if not plate then HideSparkle(); return end
    local r, g, b = Colour(kind)
    ShowSparkle(plate, F.Get("style"), r, g, b)
end

-- The plate can arrive a moment after the target it belongs to: one more
-- look shortly after a target change, and only while nothing is drawn.
local looking = false
local function EvaluateSoon()
    if looking then return end
    looking = true
    C_Timer.After(0.15, function()
        looking = false
        Evaluate()
    end)
end

-------------------------------------------------------------------------------
--  Held CVars
-------------------------------------------------------------------------------
-- How far a nameplate may show. The sparkle hangs on the target's plate, and
-- the client hands a plate out only within its own nameplate distance, so the
-- sparkle's range is taken only as far as that allows: Forever shortens the
-- reach for a value above its own default, so the default is the ceiling. nil
-- when the player's value already reaches far enough.
local function WantPlateDistance()
    local range = F.Get("range")
    local cap = tonumber(C_CVar.GetCVarDefault("nameplateMaxDistance"))
    local want = cap and math.min(range, cap) or range
    local cur = tonumber(C_CVar.GetCVar("nameplateMaxDistance"))
    if cur and cur >= want then return nil end
    return math.ceil(want)
end

-- The client's soft-target settings: targeting on for both input styles
-- (Enum.SoftTargetEnableFlags.Any, the value the Fishing key sets), its
-- reach and arc, and targets kept out of reach as well, so an object is
-- marked before it can be used.
local function Wanted()
    local range = F.Get("range")
    local want = {
        softTargetInteract = 3,
        SoftTargetInteractRange = range,
        SoftTargetInteractArc = 2,
        SoftTargetInteractOnlyInRange = 0,
        SoftTargetInteractRangeIsHard = 0,
    }
    -- The game's own loot sparkle, turned off for a player who wants this one
    -- alone (it is the client's setting, so it is a hold like the others).
    if F.Get("hideGameSparkle") then want.outlineModeShowLootEffectWhenDisabled = 0 end
    local plate = WantPlateDistance()
    if plate then want.nameplateMaxDistance = plate end
    return want
end

-- Takes the holds, remembering what each CVar was before the first hold.
-- A CVar the client does not know, or one already at the wanted value, is
-- left alone.
local function Hold()
    local cfg = F.Cfg()
    local was = cfg.held or {}
    cfg.held = was
    for name, value in pairs(Wanted()) do
        local want = tostring(value)
        local cur = C_CVar.GetCVar(name)
        if cur ~= nil and cur ~= want then
            if EllesmereUI.HoldCVar(name, want, OWNER) and was[name] == nil then was[name] = cur end
        end
    end
end

-- A hold the settings no longer want goes back to the player's value at once,
-- so a switch turned off inside the page takes effect without a reload.
local function Prune()
    local held = F.Read().held
    if not held then return end
    local values = Wanted()
    for name, value in pairs(held) do
        if values[name] == nil then
            EllesmereUI.ReleaseCVar(name, value, OWNER)
            held[name] = nil
        end
    end
end

local function Release()
    local held = F.Read().held
    if not held then return end
    for name, value in pairs(held) do
        EllesmereUI.ReleaseCVar(name, value, OWNER)
    end
    F.Cfg().held = nil
end

-- A graphics preset puts the client's own values back: write the held names
-- again (only those, so a player's change to anything else stands).
local function Reassert()
    local held = F.Read().held
    if not held then return end
    local values = Wanted()
    for name in pairs(held) do
        local want = values[name]
        if want ~= nil and C_CVar.GetCVar(name) ~= tostring(want) then
            EllesmereUI.HoldCVar(name, tostring(want), OWNER)
        end
    end
end

local function ReassertLater()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("SparklesCVars", Reassert)
        return
    end
    Reassert()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local WATCH = {
    "PLAYER_SOFT_INTERACT_CHANGED",  -- the target moved: the sparkle follows it
    "NAME_PLATE_UNIT_ADDED",         -- the plate the sparkle hangs on
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_ENTERING_WORLD",
    "LOOT_OPENED",                   -- containers the loot window teaches
    "CVAR_UPDATE",                   -- a graphics preset reset the held CVars
}
-- A profession learned or dropped, while the ore and herb kinds follow them.
local AUTO_WATCH = { "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "CVAR_UPDATE" then
        local changed = type(arg1) == "string" and arg1:lower()
        if changed == "graphicsquality" or changed == "raidgraphicsquality" then
            ReassertLater()
            Evaluate()
        end
    elseif event == "SPELLS_CHANGED" or event == "SKILL_LINES_CHANGED" then
        if AutoRead() then Evaluate() end
    elseif event == "LOOT_OPENED" then
        LearnContainers()
        Evaluate()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ReassertLater()
        Evaluate()
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        Evaluate()
        if not onPlate then EvaluateSoon() end
    else
        Evaluate()
    end
end)

-------------------------------------------------------------------------------
--  The options page's preview
-------------------------------------------------------------------------------
-- A sample plate in the content header with the sparkle under it, drawn with
-- the style on the page and the colour of the kind its eye picked (nil: the
-- eye is off). The frames outlive a page rebuild, as the other pages'
-- previews do, so they are made once and taken over by the next build.
local PREVIEW_H = 150
local PREVIEW_NAMES = {
    ore = "Ore Vein", herb = "Herb", chest = "Treasure Chest",
    quest = "Quest Object", corpse = "Dead Body", bobber = "Fishing Bobber",
}
local preview
local previewKind = "ore"

-- The preview's layers are the page's style; a style change makes them anew.
local function PreviewStyle(style)
    local v = preview
    if v.style == style then return end
    v.style = style
    for i = 1, #v.layers do
        local f = v.layers[i].frame
        v.layers[i].group:Stop()
        f:Hide()
        f:SetParent(nil)
    end
    v.layers = {}
    v.playing = false
    local specs = STYLES[style] or STYLES.glow
    for i = 1, #specs do v.layers[i] = BuildLayer(v.host, specs[i]) end
end

-- One repaint for the lot: the name, the colours and whether the sparkle runs.
local function RefreshPreview()
    local v = preview
    if not v then return end
    local kind = previewKind
    v.name:SetText(kind and PREVIEW_NAMES[kind] or "")
    PreviewStyle(F.Get("style"))
    local r, g, b = 1, 1, 1
    if kind then r, g, b = Colour(kind) end
    local on = kind ~= nil
    for i = 1, #v.layers do
        local layer = v.layers[i]
        layer.texture:SetVertexColor(r, g, b)
        if on ~= v.playing then
            if on then layer.frame:Show(); layer.group:Play() else layer.group:Stop(); layer.frame:Hide() end
        end
    end
    v.playing = on
end

local function CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local v = preview
    if not v then
        v = { layers = {} }
        v.view = CreateFrame("Frame", nil, parent)
        v.view:SetHeight(PREVIEW_H)
        v.view:SetScript("OnShow", RefreshPreview)
        v.view:SetScript("OnHide", function()
            v.playing = false
            for i = 1, #v.layers do v.layers[i].group:Stop() end
        end)
        local plate = CreateFrame("Frame", nil, v.view)
        plate:SetSize(150, 12)
        plate:SetPoint("CENTER", v.view, "CENTER", 0, 2)
        local fill = plate:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0.24, 0.24, 0.27, 1)
        EllesmereUI.PP.CreateBorder(plate, 0, 0, 0, 1, 1, "OVERLAY", 2)
        v.name = EllesmereUI.MakeFont(v.view, 12, nil, 1, 1, 1, 1)
        v.name:SetPoint("BOTTOM", plate, "TOP", 0, 5)
        v.host = CreateFrame("Frame", nil, v.view)
        v.host:SetSize(SIZE, SIZE)
        v.host:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
        v.host:EnableMouse(false)
        v.previewHeight = PREVIEW_H
        preview = v
    end
    v.view:SetParent(parent)
    v.view:ClearAllPoints()
    v.view:SetPoint("TOPLEFT")
    v.view:SetPoint("TOPRIGHT")
    v.view:Show()
    RefreshPreview()
    if onHeightChanged then onHeightChanged(PREVIEW_H) end
    return v
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
-- Login and the options; takes effect at once in both directions. The CVars
-- only change out of combat: in combat the apply waits for its end.
local booted = false
local function Apply()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("Sparkles", Apply)
        return
    end
    if not booted then
        -- Whatever a reload or a disconnect left held goes back first.
        booted = true
        Release()
    end
    if not F.Enabled() then
        HideSparkle()
        Release()
        ev:UnregisterAllEvents()
        return
    end
    Prune()
    Hold()
    for i = 1, #WATCH do ev:RegisterEvent(WATCH[i]) end
    if AutoRead() then
        for i = 1, #AUTO_WATCH do ev:RegisterEvent(AUTO_WATCH[i]) end
    else
        for i = 1, #AUTO_WATCH do ev:UnregisterEvent(AUTO_WATCH[i]) end
    end
    Evaluate()
end

-- Options-page entry points.
EllesmereUI._Sparkles = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Color = Colour,
    Refresh = Evaluate,
    STYLE_NAMES = STYLE_NAMES,
    STYLE_ORDER = STYLE_ORDER,
    -- Following this character's professions: the switch, whether a kind is
    -- one of the two it follows, and what a kind shows right now.
    AutoOn = AutoRead,
    SetAuto = AutoWrite,
    FollowsProfession = function(kind) return AUTO_SKILL[kind] ~= nil end,
    KindOn = KindOn,
    Gathering = GatheringText,
    -- The page's live preview in the content header, and the eye that picks
    -- which kind's colour it shows (nil: no sparkle drawn).
    CreateSettingsPreview = CreateSettingsPreview,
    RefreshPreview = RefreshPreview,
    PreviewKind = function() return previewKind end,
    SetPreviewKind = function(kind)
        previewKind = kind
        RefreshPreview()
    end,
    SetColor = function(kind, r, g, b)
        local cfg = F.Cfg()
        cfg.colors = cfg.colors or {}
        cfg.colors[kind] = { r = r, g = g, b = b }
        Evaluate()
        if previewKind == kind then RefreshPreview() end
    end,
}

F.Start(Apply)
