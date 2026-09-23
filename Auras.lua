-- Auras: reads the player's auras and weapon enchants into plain entry
-- tables. Every value that comes back from the client passes through the
-- secret guard, so a restricted field is simply absent.

local _, BL = ...

local Auras = {}
BL.Auras = Auras

Auras.MAX = 64

local WEAPON_SLOT_TO_INVENTORY = { [0] = 16, [1] = 17, [2] = 18 }

local function plainNumber(v)
    v = BL.Plain(v)
    if type(v) == "number" then return v end
    return nil
end

-- Returns the entry list and a flag that is true when the client refused
-- a read (in combat, secret auras make the index API error instead of
-- returning data); the caller decides what to show in that case.
function Auras.Collect(filter)
    local entries = {}
    local restricted = false
    for index = 1, Auras.MAX do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
        if not ok then
            restricted = true
            break
        end
        if data == nil then break end
        data = BL.PlainTable(data)
        if data then
            local expiration = plainNumber(data.expirationTime)
            -- A secret expiration can't be sorted or printed, but the
            -- Cooldown widget accepts it as-is; keep the raw values for that.
            local secretExpiration, secretDuration
            if expiration == nil and data.expirationTime ~= nil then
                secretExpiration, secretDuration = data.expirationTime, data.duration
            end
            entries[#entries + 1] = {
                secretExpiration = secretExpiration,
                secretDuration = secretDuration,
                kind = "aura",
                filter = filter,
                index = index,
                auraInstanceID = plainNumber(data.auraInstanceID),
                name = BL.Plain(data.name),
                icon = BL.Plain(data.icon),
                spellId = plainNumber(data.spellId),
                applications = plainNumber(data.applications) or 0,
                duration = plainNumber(data.duration),
                expirationTime = expiration,
                sourceUnit = BL.Plain(data.sourceUnit),
                dispelName = BL.Plain(data.dispelName),
                timed = expiration ~= nil and expiration > 0,
            }
        end
    end
    return entries, restricted
end

-- The enchant's own name is only available from the item tooltip: the
-- first green line, minus any "(30 min)" suffix.
local function enchantName(invSlot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", invSlot)
    info = ok and BL.PlainTable(info) or nil
    local lines = info and BL.PlainTable(info.lines)
    if not lines then return nil end
    for i = 2, #lines do
        local line = BL.PlainTable(lines[i])
        local color = line and BL.PlainTable(line.leftColor)
        local text = line and BL.Plain(line.leftText)
        if color and type(text) == "string" then
            local r, g, b = BL.Plain(color.r), BL.Plain(color.g), BL.Plain(color.b)
            if type(g) == "number" and g > 0.9 and (r or 0) < 0.2 and (b or 0) < 0.2 then
                text = string.gsub(text, "%s*%(.-%)%s*$", "")
                if text ~= "" then return text end
            end
        end
    end
    return nil
end

-- Returns the entry list and a flag that is true when the client refused
-- the read. skipNames leaves out the tooltip lookup for the enchant's
-- name (the bar's timer tick doesn't need it).
function Auras.CollectWeapons(skipNames)
    local entries = {}
    if not (C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot) then return entries, false end
    local now = BL.Clock()
    local slots = {}
    for _, slotID in pairs(Enum.WeaponSlot) do slots[#slots + 1] = slotID end
    table.sort(slots)
    for _, slotID in ipairs(slots) do
        local invSlot = WEAPON_SLOT_TO_INVENTORY[slotID]
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slotID)
        if not ok then return {}, true end
        list = BL.PlainTable(list)
        if invSlot and list then
            for _, enchant in ipairs(list) do
                enchant = BL.PlainTable(enchant)
                if enchant and BL.Plain(enchant.hasEnchant) then
                    local ms = plainNumber(enchant.timeLeft) or 0
                    entries[#entries + 1] = {
                        kind = "weapon",
                        slot = invSlot,
                        weaponSlot = slotID,
                        enchantType = plainNumber(enchant.enchantType) or 0,
                        name = (not skipNames and enchantName(invSlot)) or "Weapon Enchant",
                        icon = BL.Plain(enchant.enchantIconID) or GetInventoryItemTexture("player", invSlot),
                        applications = plainNumber(enchant.charges) or 0,
                        expirationTime = now + ms / 1000,
                        timed = true,
                    }
                end
            end
        end
    end
    return entries, false
end

-- Structural identity of an entry list: which auras, in which order.
-- Timers and stacks are deliberately left out.
function Auras.Signature(entries)
    local parts = {}
    for i = 1, #entries do
        local e = entries[i]
        if e.kind == "weapon" then
            parts[i] = "w" .. tostring(e.slot)
        else
            parts[i] = "a" .. tostring(e.auraInstanceID or e.index)
        end
    end
    return table.concat(parts, ",")
end
