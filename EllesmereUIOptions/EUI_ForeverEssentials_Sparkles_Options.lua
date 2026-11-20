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

    ---------------------------------------------------------------------------
    --  LOOT SPARKLES: the switch and the range it reaches, then the style and
    --  the game's own sparkle, then a switch with a swatch and a preview eye
    --  for each kind.
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
          tooltip = "How many yards away an object still sparkles. The game hands out a nameplate only within its own nameplate distance, so a target it does not mark cannot be reached.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.Get("range") end,
          setValue = function(v) Set("range", v) end }
    );  y = y - h

    local styleValues, styleOrder = {}, {}
    for i = 1, #SP.STYLE_ORDER do
        local key = SP.STYLE_ORDER[i]
        styleValues[key] = SP.STYLE_NAMES[key]
        styleOrder[i] = key
    end

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Sparkle Style",
          values = styleValues, order = styleOrder,
          tooltip = "How the sparkle moves: a soft glow, a rising beam, a flaring star, or stars twinkling.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.Get("style") end,
          setValue = function(v)
              SP.Cfg().style = v
              SP.Refresh()
              SP.RefreshPreview()
          end },
        { type = "toggle", text = "Hide the Game's Loot Sparkle",
          tooltip = "Turns off the game's own sparkle on lootable bodies and quest objects, so the sparkle here is the only one. The game shares that setting with every loot effect it draws, so anything not sparkled here loses it too.",
          disabled = off, disabledTooltip = "Loot Sparkles",
          getValue = function() return SP.Get("hideGameSparkle") == true end,
          setValue = function(v) Set("hideGameSparkle", v) end }
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
            return not off() and SP.Get(kind) == true
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

    -- One kind's row entry: its switch, and the controls that go beside it.
    local function KindCfg(kind, label, tooltip)
        return { type = "toggle", text = label, tooltip = tooltip,
            disabled = off, disabledTooltip = "Loot Sparkles",
            getValue = function() return SP.Get(kind) == true end,
            setValue = function(v)
                SP.Cfg()[kind] = v
                -- A kind switched off leaves the preview, as its eye greys.
                if not v and SP.PreviewKind() == kind then SP.SetPreviewKind(nil) end
                SP.Refresh()
                RefreshEyes()
            end }
    end

    local KIND_ROWS = {
        { "ore", "Ore Veins", "Ore veins, in the color you pick." },
        { "herb", "Herbs", "Herbs, in the color you pick." },
        { "chest", "Treasure Chests", "Chests, crates and barrels, whatever the game calls them: the first loot of a kind teaches the sparkle which object it is." },
        { "quest", "Quest Objects", "Objects the quest log ties to a quest you are on." },
        { "corpse", "Dead Bodies", "Creatures that are down. Turn the game's own loot sparkle off above to see this one alone." },
        { "bobber", "Fishing Bobber", "Your fishing bobber, whenever the game's targeting picks it up." },
    }
    local BLANK = EllesmereUI.BlankRowCfg
    for i = 1, #KIND_ROWS, 2 do
        local left = KIND_ROWS[i]
        local right = KIND_ROWS[i + 1]
        local row
        row, h = W:DualRow(parent, y,
            KindCfg(left[1], left[2], left[3]),
            right and KindCfg(right[1], right[2], right[3]) or BLANK()
        );  y = y - h
        AddKindControls(row._leftRegion, left[1])
        if right then AddKindControls(row._rightRegion, right[1]) end
    end

    return math.abs(y)
end
