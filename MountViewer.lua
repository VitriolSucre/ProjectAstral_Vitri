
local PA = ProjectAstral

-- Full-screen mount viewer: only the mount's 3D model, on black. Opened from the
-- Store tab (View button or Ctrl-click on a mount in Store Mounts or the Token Store).
-- Drag to turn, mouse wheel to zoom, click, right-click or Esc to close.
--
-- 3.3.5 has no item -> creature lookup, so the model comes from, in order: a
-- creature/display id the server sent with the store entry, or the matching mount
-- this character already knows (GetCompanionInfo). Otherwise it says so and stays shut.

local MV = {}
PA.MountViewer = MV

local SOLID = "Interface\\Buttons\\WHITE8X8"
local CREATURE_KEYS = { "creature", "creatureId", "creatureID", "creatureEntry", "npc", "npcId" }
local DISPLAY_KEYS  = { "display", "displayId", "displayID", "displayInfo", "modelId" }
local PREFIXES = { "reins of the ", "reins of ", "whistle of the ", "whistle of ",
                   "horn of the ", "horn of ", "bridle of the " }
local SUFFIXES = { " reins", " bridle", " whistle", " horn", " harness" }

local viewer, model, hint

local function Norm(s)
    s = type(s) == "string" and s:lower() or ""
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _, p in ipairs(PREFIXES) do
        if s:sub(1, #p) == p then s = s:sub(#p + 1); break end
    end
    for _, x in ipairs(SUFFIXES) do
        if #s > #x and s:sub(-#x) == x then s = s:sub(1, -#x - 1); break end
    end
    return s
end

-- a mount this character knows whose name matches the store item's name
local function FindKnown(name, spellId)
    local n = (type(GetNumCompanions) == "function" and GetNumCompanions("MOUNT")) or 0
    local want = Norm(name)
    local partial
    for i = 1, n do
        local creatureID, cname, cspell = GetCompanionInfo("MOUNT", i)
        if creatureID then
            if spellId and cspell == spellId then return creatureID end
            local c = Norm(cname)
            if want ~= "" and c ~= "" then
                if c == want then return creatureID end
                if not partial and #want >= 4 and #c >= 4
                   and (want:find(c, 1, true) or c:find(want, 1, true)) then
                    partial = creatureID
                end
            end
        end
    end
    return partial
end

-- opts: { item = itemId, name = itemName, spell = spellId, raw = serverEntry, meta = itemMeta }
function MV.Resolve(opts)
    opts = opts or {}
    if tonumber(opts.creature) then return "creature", tonumber(opts.creature) end   -- known mounts (MountJournal.lua)
    for _, t in ipairs({ opts.raw, opts.meta }) do
        if type(t) == "table" then
            for _, k in ipairs(CREATURE_KEYS) do
                local v = tonumber(t[k])
                if v and v > 0 then return "creature", v end
            end
            for _, k in ipairs(DISPLAY_KEYS) do
                local v = tonumber(t[k])
                if v and v > 0 then return "display", v end
            end
        end
    end
    local name = opts.name
    if (not name or name == "") and opts.item then name = GetItemInfo(opts.item) end
    local c = FindKnown(name, opts.spell)
    if c then return "creature", c end
end

local function ApplyModel()
    if not model._id then return end
    if model._kind == "creature" then
        model:SetCreature(model._id)
    elseif model.SetDisplayInfo then
        model:SetDisplayInfo(model._id)
    end
    if model.SetModelScale then model:SetModelScale(model._scale) end
end

local function Build()
    viewer = CreateFrame("Frame", "PAMountViewer", UIParent)
    viewer.__paUnified = true   -- unified look: Theme.lua keeps its navy
    viewer:SetFrameStrata("FULLSCREEN_DIALOG")
    viewer:SetAllPoints(UIParent)
    viewer:EnableMouse(true)
    viewer:EnableMouseWheel(true)
    viewer:Hide()
    tinsert(UISpecialFrames, "PAMountViewer")   -- Esc closes it

    local bg = viewer:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(SOLID)
    bg:SetAllPoints()
    bg:SetVertexColor(0, 0, 0, 1)

    model = CreateFrame("PlayerModel", nil, viewer)
    model:SetAllPoints(viewer)
    model._facing, model._scale = 0.6, 1
    model:SetScript("OnShow", ApplyModel)       -- a model frame drops its model while hidden

    -- faint controls hint that fades away, so only the mount is left on screen
    hint = viewer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", viewer, "BOTTOM", 0, 24)
    hint:SetText("Drag to turn  ·  Scroll to zoom  ·  Click or Esc to close")

    viewer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local x = GetCursorPosition()
            self._downX, self._lastX = x, x
        end
    end)
    viewer:SetScript("OnMouseUp", function(self, button)
        local x = GetCursorPosition()
        local clicked = button == "RightButton"
            or (button == "LeftButton" and self._downX and math.abs(x - self._downX) < 4)
        self._downX, self._lastX = nil, nil
        if clicked then self:Hide() end
    end)
    viewer:SetScript("OnMouseWheel", function(_, delta)
        model._scale = math.max(0.4, math.min(3, model._scale + delta * 0.15))
        if model.SetModelScale then model:SetModelScale(model._scale) end
    end)
    viewer:SetScript("OnUpdate", function(self, dt)
        if self._lastX then                  -- drag to turn, otherwise a slow spin
            local x = GetCursorPosition()
            model._facing = model._facing + (x - self._lastX) * 0.01
            self._lastX = x
        else
            model._facing = model._facing + dt * 0.25
        end
        model:SetFacing(model._facing)
        self._hintT = (self._hintT or 0) + dt
        if self._hintT > 2.5 then hint:SetAlpha(math.max(0, 1 - (self._hintT - 2.5))) end
    end)
    viewer:SetScript("OnHide", function(self) self._downX, self._lastX = nil, nil end)
end

-- returns true when the viewer opened
function MV.Show(opts)
    local kind, id = MV.Resolve(opts)
    if kind == "display" and not (model or CreateFrame("PlayerModel")).SetDisplayInfo then kind = nil end
    if not kind then
        UIErrorsFrame:AddMessage("No 3D model for this mount yet: it shows once you've learned it.",
            1.0, 0.8, 0.3, 1.0)
        return false
    end
    if not viewer then Build() end
    GameTooltip:Hide()
    model._kind, model._id = kind, id
    model._facing, model._scale = 0.6, 1
    viewer._hintT = 0
    hint:SetAlpha(1)
    if viewer:IsShown() then ApplyModel() else viewer:Show() end
    return true
end
