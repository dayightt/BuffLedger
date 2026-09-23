-- DebuffBar: what is on you, soonest first, bordered by dispel type. Same
-- machinery as the buff bar with its own settings scope; no categories.

local _, BL = ...

BL.DebuffBar = BL.CreateBar({ scope = "debuff", frameName = "BuffLedgerDebuffBar", label = "BuffLedger debuffs - drag to move" })
