if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Sparkles_Options.lua
--  Builds the "Loot Sparkles" page inside the Forever Essentials module: a
--  live preview of the sparkle in the content header, then its settings.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = EllesmereUI._Sparkles.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._EUI_SparklesHeaderBuilder = HeaderBuilder

_G._EUI_BuildSparklesPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local SP = EllesmereUI._Sparkles
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h, hdr
    parent._showRowDivider = true

    EllesmereUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not SP.Get("enabled")
    end
    local function Set(key, v)
        SP.Cfg()[key] = v
        SP.Apply()
    end

    -- What the client took for the reach when this page was built, so the
    -- range row can tell when the answer needs the page again.
    local builtReach = SP.RangeLearned()

    -- The page's first line, as the Friendly Plates page has its instance note:
    -- the sparkle sits on the plate of the game's interact target, so interact
    -- targeting has to be on, and this says who turns it on.
    local note
    if SP.RespectInteract() then
        note = SP.InteractOff()
            and "Interact Key is off in Options > Controls: nothing will sparkle until you turn it on."
            or "The Interact Key setting is left as you set it."
    else
        note = "Loot Sparkles turns the game's Interact Key on while it is enabled, and puts your own setting back when it is off."
    end
    y = EllesmereUI.BuildNoteRow(parent, y, note, { warn = true })

    ---------------------------------------------------------------------------
    --  LOOT SPARKLES: the switch and the range it reaches, the profession
    --  switch, then the game's own sparkle and the Interact Key choice.
    ---------------------------------------------------------------------------
    hdr, h = W:SectionHeader(parent, "LOOT SPARKLES", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Loot Sparkles",
          tooltip = "Sparkles the interactable the game's targeting points at - an ore vein, a herb, a chest, a quest object, a lootable body or your fishing bobber - in the color you pick for its kind.",
          getValue = function() return not off() end,
          setValue = function(v)
              SP.Cfg().enabled = v
              SP.Apply()
              EllesmereUI:RefreshPage()  -- every row below and the eye grey out with it
          end },
        { type = "slider", text = "Sparkle Range",
          min = 15, max = 40, step = 1, isPercent = false,
          tooltip = "How many yards away an object still sparkles. The game marks an interactable only as far as its own interact range and nameplate distance reach, and says so below the slider when that is shorter.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.Get("range") end,
          setValue = function(v)
              SP.Cfg().range = v
              SP.Apply()
              -- The note below is built from what the client took, so the page
              -- is rebuilt only when that answer changes, not on every step of
              -- a drag.
              if SP.RangeLearned() ~= builtReach then EllesmereUI:RefreshPage() end
          end }
    );  y = y - h

    -- The game's own ceiling, whenever it is under the setting: the slider
    -- says what was asked for, this says what the client gives.
    local reach = SP.RangeLearned()
    if reach and reach < SP.Get("range") then
        y = EllesmereUI.BuildNoteRow(parent, y,
            ("The game marks an interactable only within %d yards here, so a longer Sparkle Range is not used."):format(math.floor(reach)),
            { warn = true })
    end

    local styleValues, styleOrder = {}, {}
    for i = 1, #SP.STYLE_ORDER do
        local key = SP.STYLE_ORDER[i]
        styleValues[key] = SP.STYLE_NAMES[key]
        styleOrder[i] = key
    end

    -- Following this character's professions: the ore and herb switches are
    -- kept but ignored while it is on, so it is their own row above them. The
    -- note beside it names the professions it found, so the switches below
    -- greying makes sense at a glance.
    local gathered = SP.Gathering()
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Follow My Professions",
          tooltip = "Turns the ore and herb sparkles on for the professions this character has: Mining for ore, Herbalism for herbs, off for the one it cannot gather. Your own switches for those two are kept and come back when this is turned off. This character only.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.AutoOn() end,
          setValue = function(v)
              SP.SetAuto(v)
              SP.Apply()
              EllesmereUI:RefreshPage()  -- the ore and herb rows follow it
          end },
        { type = "label", text = (gathered ~= "" and gathered) or "No gathering profession",
          tooltip = "The gathering professions this character has. The ore and herb sparkles follow them while the switch beside it is on." }
    );  y = y - h

    -- The game's own sparkle, and whether the Interact Key is ours to turn on.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide the Game's Loot Sparkle",
          tooltip = "Turns off the game's own sparkle on lootable bodies and quest objects, so the sparkle here is the only one. The game shares that setting with every loot effect it draws, so anything not sparkled here loses it too.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.Get("hideGameSparkle") == true end,
          setValue = function(v) Set("hideGameSparkle", v) end },
        { type = "toggle", text = "Leave My Interact Key Alone",
          tooltip = "Never changes the game's Interact Key setting. The sparkle sits on the plate of the interact target, so with this on it appears only while you have Interact Key turned on yourself (Options > Controls); with it off, turning Loot Sparkles on turns the key on and turning it off puts your setting back.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.RespectInteract() end,
          setValue = function(v)
              SP.Cfg().respectInteract = v
              SP.Apply()
              EllesmereUI:RefreshPage()  -- the note at the top reads the new choice
          end }
    );  y = y - h

    -- Every row's eye is repainted when one of them is picked, so only the lit
    -- one shows an open eye.
    local eyeRefreshes = {}
    local function RefreshEyes()
        for i = 1, #eyeRefreshes do eyeRefreshes[i]() end
    end

    -- The row's toggle is DualRow's; the swatch and the eye chain left of it.
    -- kind is the settings key, and the kind the colours and the preview use.
    local function AddKindControls(rgn, kind)
        if EllesmereUI._prebuilding or not rgn then return end
        local function live()
            return not off() and SP.KindOn(kind) == true
        end

        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
            function() return SP.Color(kind) end,
            function(r, g, b) SP.SetColor(kind, r, g, b) end, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        swatch:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, "Sparkle Color")
        end)
        swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- The swatch greys with the feature, as the switches do.
        EllesmereUI.RegisterWidgetRefresh(function()
            local shown = not off()
            swatch:SetAlpha(shown and 1 or 0.3)
            swatch:EnableMouse(shown)
            updateSwatch()
        end)

        local eye = EllesmereUI._Pool.CreateFrame("Button", nil, rgn)
        eye:SetSize(26, 26)
        PP.Point(eye, "RIGHT", rgn._lastInline, "LEFT", -8, 0)
        eye:SetFrameLevel(rgn:GetFrameLevel() + 5)
        rgn._lastInline = eye
        local tex = eye:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        -- The art is named the other way round: the "invisible" file is the
        -- open eye.
        local function refreshEye()
            tex:SetTexture(SP.PreviewKind() == kind and EllesmereUI.EYE_INVISIBLE_ICON
                or EllesmereUI.EYE_VISIBLE_ICON)
            EllesmereUI.SetGlyphAlpha(eye, live() and 0.4 or 0.15)
        end
        eyeRefreshes[#eyeRefreshes + 1] = refreshEye
        refreshEye()
        EllesmereUI.RegisterWidgetRefresh(refreshEye)
        eye:SetScript("OnClick", function()
            if not live() then return end
            -- Off when this kind is the one showing, on when it is not.
            if SP.PreviewKind() == kind then
                SP.SetPreviewKind(nil)
            else
                SP.SetPreviewKind(kind)
            end
            RefreshEyes()
        end)
        eye:SetScript("OnEnter", function(self)
            if live() then EllesmereUI.SetGlyphAlpha(self, 0.7) end
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eye:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
            refreshEye()
        end)
    end

    -- One kind's row: its switch (with the swatch and the preview eye beside
    -- it) on the left, its own effect on the right. An ore or herb row follows
    -- this character's professions while that is on: it shows what the
    -- profession gives and greys, its own switch kept.
    local KIND_ROWS = {
        { "ore", "Ore Veins", "Ore veins, in the color you pick." },
        { "herb", "Herbs", "Herbs, in the color you pick." },
        { "chest", "Treasure Chests", "Chests, crates and barrels, whatever the game calls them: the first loot of a kind teaches the sparkle which object it is." },
        { "quest", "Quest Objects", "Objects the quest log ties to a quest you are on." },
        { "corpse", "Dead Bodies", "Creatures that are down. Turn the game's own loot sparkle off above to see this one alone." },
        { "bobber", "Fishing Bobber", "Your fishing bobber, whenever the game's targeting picks it up." },
    }

    -- The effect is each kind's own, so a body can wear a beam while ore wears
    -- a glow. It is the sample the top of the page draws, too.
    _, h = W:SectionHeader(parent, "WHAT SPARKLES", y);  y = y - h

    for i = 1, #KIND_ROWS do
        local kind, label, tooltip = KIND_ROWS[i][1], KIND_ROWS[i][2], KIND_ROWS[i][3]
        local follows = SP.FollowsProfession(kind)
        local row
        row, h = W:DualRow(parent, y,
            { type = "toggle", text = label, tooltip = tooltip,
              disabled = function() return off() or (follows and SP.AutoOn()) end,
              disabledTooltip = function()
                  if off() then return "Loot Sparkles" end
                  return "Follow My Professions"
              end,
              getValue = function() return SP.KindOn(kind) == true end,
              setValue = function(v)
                  SP.Cfg()[kind] = v
                  -- A kind switched off leaves the preview, as its eye greys.
                  if not v and SP.PreviewKind() == kind then SP.SetPreviewKind(nil) end
                  SP.Refresh()
                  RefreshEyes()
              end },
            { type = "dropdown", text = "Effect",
              values = styleValues, order = styleOrder,
              tooltip = "How this kind's sparkle moves: a soft glow, a rising beam, a flaring star, or stars twinkling.",
              disabled = off, disabledTooltip = "Loot Sparkles",
              getValue = function() return SP.Effect(kind) end,
              setValue = function(v) SP.SetEffect(kind, v) end }
        );  y = y - h
        AddKindControls(row._leftRegion, kind)
    end

    return math.abs(y)
end
