--[[
    Main (client) — the interface, built entirely in code.

    The client is a dumb terminal. It renders whatever view model the server
    sends it and sends back intents ("ageUp", "choose 2", "begin"). It never
    computes an outcome and never edits its own numbers — everything on screen
    came off the wire.

    One screen, four states:
        create  -> race + name + the sheet, shown before play begins
        play    -> stat panel, event card, Age Up
        outcome -> the paragraph and its delta chips, then Continue
        dead    -> epitaph and Play again
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hide the pieces of Roblox's own HUD that belong to a body we do not have.
-- The health bar is the loud one: with no ground under a spawned character it
-- drains to nothing, plays the death sound and comes back, over and over.
-- SetCoreGuiEnabled throws if CoreGui is not ready yet, so it retries.
local StarterGui = game:GetService("StarterGui")
task.spawn(function()
    for _ = 1, 20 do
        local ok = pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
        end)
        if ok then
            return
        end
        task.wait(0.25)
    end
end)

-- Any character that does slip through (a plugin, a respawn request) keeps a
-- full bar and makes no noise.
local function silence(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        humanoid.Health = humanoid.MaxHealth
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Sound") then
            descendant:Destroy()
        end
    end
end
player.CharacterAdded:Connect(silence)
if player.Character then
    silence(player.Character)
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UiKit = require(script.Parent.UiKit)

local Theme = UiKit.Theme
local actionRemote = ReplicatedStorage:WaitForChild(Config.Remotes.action)
local updateRemote = ReplicatedStorage:WaitForChild(Config.Remotes.update)

local function send(action, data)
    actionRemote:FireServer(action, data)
end

-- ===========================================================================
-- Shell
-- ===========================================================================

local screen = UiKit.create("ScreenGui", {
    Name = "NewWorldLife",
    ResetOnSpawn = false,
    -- Fill the screen edge to edge. Roblox's own top-left controls sit over the
    -- top strip, so the readouts they would cover (AGE, HEALTH) live at the far
    -- right of that strip instead.
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local root = UiKit.create("Frame", {
    Name = "Root",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Theme.background,
    BorderSizePixel = 0,
}, screen)

-- ---------------------------------------------------------------------------
-- Top bar: six numbers, always visible, never more (design brief §1.2)
-- ---------------------------------------------------------------------------

local topBar = UiKit.create("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 56),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
}, root)
UiKit.create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 20),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, topBar)
UiKit.create("UIPadding", {
    PaddingLeft = UDim.new(0, 18),
    PaddingRight = UDim.new(0, 18),
}, topBar)

local function topStat(title, width, order)
    local frame = UiKit.create("Frame", {
        Size = UDim2.new(0, width, 0, 36),
        BackgroundTransparency = 1,
        LayoutOrder = order,
    }, topBar)
    UiKit.label(frame, {
        Text = title,
        Size = UDim2.new(1, 0, 0, 14),
        Font = UiKit.FontUi,
        TextSize = 12,
        TextColor3 = Theme.textDim,
    })
    local value = UiKit.label(frame, {
        Text = "—",
        Position = UDim2.new(0, 0, 0, 14),
        Size = UDim2.new(1, 0, 0, 20),
        Font = UiKit.FontNumber,
        TextSize = 17,
    })
    return value
end

-- Health gets a bar as well as a number: it is the only number that can end
-- a run without a choice. It sits last, with AGE, so both readouts are pinned
-- to the right end of the strip, clear of Roblox's top-left controls.
local healthBlock = UiKit.create("Frame", {
    Size = UDim2.new(0, 190, 0, 36),
    BackgroundTransparency = 1,
    LayoutOrder = 7,
}, topBar)
UiKit.label(healthBlock, {
    Text = "HEALTH",
    Size = UDim2.new(1, 0, 0, 14),
    Font = UiKit.FontUi,
    TextSize = 12,
    TextColor3 = Theme.textDim,
})
local healthBar, setHealthBar = UiKit.bar(healthBlock, {
    Position = UDim2.new(0, 0, 0, 20),
    Size = UDim2.new(1, -78, 0, 10),
}, Theme.healthFill)
local healthValue = UiKit.label(healthBlock, {
    Text = "—",
    Position = UDim2.new(1, -74, 0, 14),
    Size = UDim2.new(0, 74, 0, 20),
    Font = UiKit.FontNumber,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Right,
})

local levelValue = topStat("LEVEL · EXP", 118, 1)
local coinValue = topStat("COIN", 74, 2)
local karmaValue = topStat("KARMA", 74, 3)
local notorietyValue = topStat("NOTORIETY", 84, 4)
-- The year line is the only elastic item: it absorbs whatever width is left
-- between NOTORIETY and the right-hand pair, so AGE and HEALTH land flush with
-- the right edge instead of wherever the fixed widths happen to end.
-- 750 = the fixed widths (594) + the six 20px gaps (120) + both 18px paddings.
local yearValue = UiKit.label(topBar, {
    Text = "",
    Size = UDim2.new(1, -750, 0, 20),
    LayoutOrder = 5,
    Font = UiKit.FontProse,
    TextSize = 14,
    TextColor3 = Theme.textDim,
    TextXAlignment = Enum.TextXAlignment.Right,
})
local ageValue = topStat("AGE", 54, 6)

-- ---------------------------------------------------------------------------
-- Left rail: the character sheet
-- ---------------------------------------------------------------------------

local rail = UiKit.create("ScrollingFrame", {
    Name = "Sheet",
    Size = UDim2.new(0, 268, 1, -128),
    Position = UDim2.new(0, 12, 0, 68),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, root)
UiKit.create("UICorner", { CornerRadius = UDim.new(0, 6) }, rail)
UiKit.create("UIPadding", {
    PaddingTop = UDim.new(0, 12),
    PaddingBottom = UDim.new(0, 12),
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12),
}, rail)
UiKit.create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 5),
}, rail)

-- ---------------------------------------------------------------------------
-- Centre: the event card
-- ---------------------------------------------------------------------------

local card = UiKit.panel(root, {
    Name = "Card",
    Size = UDim2.new(1, -300, 1, -168),
    Position = UDim2.new(0, 288, 0, 68),
}, 22)

local choicesFrame = UiKit.create("Frame", {
    Name = "Choices",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 0),
}, card)

-- ---------------------------------------------------------------------------
-- Bottom: the only button that matters
-- ---------------------------------------------------------------------------

local ageUpButton = UiKit.button(root, {
    Name = "AgeUp",
    Text = "Age Up",
    Size = UDim2.new(0, 240, 0, 46),
    Position = UDim2.new(0.5, 138, 1, -60),
    AnchorPoint = Vector2.new(0.5, 0),
    BackgroundColor3 = Theme.accent,
    TextColor3 = Color3.fromRGB(26, 22, 14),
    Font = UiKit.FontUi,
    TextSize = 19,
}, function()
    send("ageUp")
end)

-- ---------------------------------------------------------------------------
-- Character creation screen
-- ---------------------------------------------------------------------------

local createFrame = UiKit.create("Frame", {
    Name = "Create",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Theme.background,
    BorderSizePixel = 0,
    Visible = false,
}, root)

local createPanel = UiKit.panel(createFrame, {
    Size = UDim2.new(1, -80, 1, -80),
    Position = UDim2.new(0, 40, 0, 40),
}, 24)

UiKit.label(createPanel, {
    Text = "FIRST LIGHT",
    Size = UDim2.new(1, 0, 0, 26),
    Font = UiKit.FontUi,
    TextSize = 15,
    TextColor3 = Theme.accent,
})

local birthParagraph = UiKit.label(createPanel, {
    Text = "",
    Position = UDim2.new(0, 0, 0, 40),
    Size = UDim2.new(0.5, -20, 1, -150),
    TextSize = 17,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local createInstruction = UiKit.label(createPanel, {
    Text = "",
    Position = UDim2.new(0, 0, 1, -96),
    Size = UDim2.new(0.5, -20, 0, 32),
    TextSize = 15,
    TextColor3 = Theme.textDim,
    TextWrapped = true,
})

local createSheet = UiKit.create("ScrollingFrame", {
    Name = "CreateSheet",
    Position = UDim2.new(0.5, 10, 0, 40),
    Size = UDim2.new(0.5, -10, 1, -150),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, createPanel)
UiKit.create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
}, createSheet)

local beginButton = UiKit.button(createPanel, {
    Name = "Begin",
    Text = "Begin this life",
    Size = UDim2.new(0, 240, 0, 46),
    Position = UDim2.new(0, 0, 1, -50),
    BackgroundColor3 = Theme.accent,
    TextColor3 = Color3.fromRGB(26, 22, 14),
    TextSize = 18,
}, function()
    send("begin")
end)

local rerollButton = UiKit.button(createPanel, {
    Name = "Reroll",
    Text = "Re-roll the sheet",
    Size = UDim2.new(0, 200, 0, 32),
    Position = UDim2.new(0, 250, 1, -44),
    TextSize = 15,
}, function()
    send("reroll")
end)

-- ---------------------------------------------------------------------------
-- Death screen
-- ---------------------------------------------------------------------------

local deathFrame = UiKit.create("Frame", {
    Name = "Death",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(8, 8, 10),
    BorderSizePixel = 0,
    Visible = false,
}, root)

local deathPanel = UiKit.panel(deathFrame, {
    Size = UDim2.new(1, -160, 1, -120),
    Position = UDim2.new(0, 80, 0, 60),
    BackgroundColor3 = Theme.panel,
}, 28)

-- ===========================================================================
-- Rendering
-- ===========================================================================

local attributeNames = {}
for _, attribute in ipairs(Config.Attributes) do
    attributeNames[attribute.key] = attribute.name
end

--- A small "TITLE / value" row, used all over the sheet.
local function statRow(parent, order, title, value, valueColor, width)
    local row = UiKit.create("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        LayoutOrder = order,
    }, parent)
    UiKit.label(row, {
        Text = title,
        Size = UDim2.new(1, -70, 1, 0),
        Font = UiKit.FontNumber,
        TextSize = 15,
        TextColor3 = Theme.textDim,
    })
    UiKit.label(row, {
        Text = value,
        Position = UDim2.new(1, -70, 0, 0),
        Size = UDim2.new(0, 70, 1, 0),
        Font = UiKit.FontNumber,
        TextSize = 15,
        TextColor3 = valueColor or Theme.text,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    return row
end

local function sectionHeader(parent, order, text)
    return UiKit.label(parent, {
        Text = text,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = order,
        Font = UiKit.FontUi,
        TextSize = 12,
        TextColor3 = Theme.accent,
    })
end

--- One attribute row: SHORTNAME  name ............ value
local function attributeRow(parent, order, key, value, delta)
    local row = UiKit.create("Frame", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        LayoutOrder = order,
    }, parent)
    UiKit.label(row, {
        Text = key,
        Size = UDim2.new(0, 42, 1, 0),
        Font = UiKit.FontNumber,
        TextSize = 15,
        TextColor3 = Theme.textDim,
    })
    UiKit.label(row, {
        Text = attributeNames[key] or key,
        Position = UDim2.new(0, 44, 0, 0),
        Size = UDim2.new(1, -124, 1, 0),
        TextSize = 15,
        TextColor3 = Theme.text,
    })
    local valueText = tostring(value)
    if delta and delta > 0 then
        valueText = string.format("%d (+%d)", value, delta)
    end
    UiKit.label(row, {
        Text = valueText,
        Position = UDim2.new(1, -80, 0, 0),
        Size = UDim2.new(0, 80, 1, 0),
        Font = UiKit.FontNumber,
        TextSize = 15,
        TextColor3 = delta and delta > 0 and Theme.good or Theme.text,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    return row
end

--- Rebuild the character sheet in the left rail.
local function renderRail(view)
    UiKit.clear(rail)
    local order = 1

    UiKit.label(rail, {
        Text = view.name,
        Size = UDim2.new(1, 0, 0, 24),
        LayoutOrder = order,
        TextSize = 20,
    })
    order += 1

    local subtitle = view.raceName
        or "not yet born"
    if view.phase ~= "create" then
        subtitle = string.format("%s · %s · %s", view.raceName or "—", view.stage, view.vocation or "")
    end
    UiKit.label(rail, {
        Text = subtitle,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = order,
        Font = UiKit.FontUi,
        TextSize = 13,
        TextColor3 = Theme.textDim,
    })
    order += 1

    -- Level and experience
    if view.phase ~= "create" then
        local _, setExpBar = UiKit.bar(rail, {
            Size = UDim2.new(1, 0, 0, 8),
            LayoutOrder = order,
        }, Theme.expFill)
        order += 1
        UiKit.label(rail, {
            Text = string.format(
                "Level %d · %d / %d exp",
                view.resources.level,
                view.resources.expIntoLevel,
                view.resources.expForLevel
            ),
            Size = UDim2.new(1, 0, 0, 16),
            LayoutOrder = order,
            Font = UiKit.FontNumber,
            TextSize = 13,
            TextColor3 = Theme.textDim,
        })
        order += 1
        setExpBar(view.resources.expFraction or 0)
    else
        order += 1
    end

    order += 1
    sectionHeader(rail, order, "ATTRIBUTES")
    order += 1

    local attrs = view.attrs or (view.create and view.create.preview) or {}
    local baseRoll = view.create and view.create.baseRoll or nil
    for _, key in ipairs(Config.AttributeOrder) do
        local value = attrs[key] or 0
        local delta = baseRoll and (value - (baseRoll[key] or value)) or nil
        attributeRow(rail, order, key, value, delta)
        order += 1
    end

    if view.derived then
        order += 1
        sectionHeader(rail, order, "DERIVED")
        order += 1
        local derived = view.derived
        statRow(rail, order, "HealthMax", tostring(derived.healthMax)); order += 1
        statRow(rail, order, "ManaMax", tostring(derived.manaMax)); order += 1
        statRow(rail, order, "Armour", tostring(derived.armour)); order += 1
        statRow(rail, order, "Ward", tostring(derived.ward)); order += 1
        statRow(rail, order, "Dodge%", tostring(derived.dodge)); order += 1
        statRow(rail, order, "Crit%", tostring(derived.crit)); order += 1
        statRow(rail, order, "Fortune", tostring(derived.fortune)); order += 1
        statRow(rail, order, "Carry kg", tostring(derived.carry)); order += 1
    end

    if view.notable and #view.notable > 0 then
        order += 1
        sectionHeader(rail, order, "WHAT THEY DID")
        order += 1
        for _, clause in ipairs(view.notable) do
            UiKit.label(rail, {
                Text = "· " .. clause,
                Size = UDim2.new(1, 0, 0, 30),
                LayoutOrder = order,
                TextSize = 13,
                TextColor3 = Theme.textDim,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
            })
            order += 1
        end
    end
end

local function renderTopBar(view)
    ageValue.Text = tostring(view.age)
    levelValue.Text = tostring(view.resources.level)
    coinValue.Text = tostring(view.resources.coin)
    karmaValue.Text = tostring(view.resources.karma)
    notorietyValue.Text = tostring(view.resources.notoriety)

    local healthMax = (view.derived and view.derived.healthMax) or 1
    healthValue.Text = string.format("%d / %d", math.max(0, math.floor(view.resources.health)), healthMax)
    setHealthBar(view.resources.health / math.max(1, healthMax))
    healthBar.BackgroundColor3 = Color3.fromRGB(12, 12, 15)

    yearValue.Text = view.yearLine or ""
    if view.phase == "create" then
        yearValue.Text = ""
    end
    if view.lifespan and view.age >= 50 then
        local years = math.max(0, view.lifespan - view.age)
        yearValue.Text = string.format("%s   ·   you have perhaps %d years", yearValue.Text, years)
    end
end

--- The centre of the screen: event card, outcome, or a quiet year.
local function renderCard(view)
    UiKit.clear(card)

    local titleText, bodyText, noteText = "", "", nil
    local buttons = {}
    local chipText = nil

    if view.phase == "event" and view.event then
        titleText = view.event.title
        bodyText = view.event.text
        -- §5.1 fairness, made structural: a card that leads into a fight says so
        -- in prose, and shows what losing costs and what health goes down the
        -- hatch with you, BEFORE the player chooses.
        if view.event.combat then
            local block = view.event.combat
            local lines = {}
            if block.warning then
                lines[#lines + 1] = block.warning
            end
            if block.stakes then
                lines[#lines + 1] = block.stakes
            end
            lines[#lines + 1] = string.format(
                "You would go in on %d of %d health.", block.health, block.healthMax
            )
            if block.lowHealth then
                lines[#lines + 1] = block.lowHealth
            end
            bodyText = bodyText .. "\n\n" .. table.concat(lines, " ")
        end
        for _, choice in ipairs(view.event.choices) do
            local label = choice.label
            if choice.startsCombat then
                label = string.format("%s    [ FIGHT ]", choice.label)
            elseif choice.warn and choice.warn ~= "safe" then
                label = string.format("%s   %s", choice.label, choice.warn)
            end
            buttons[#buttons + 1] = {
                text = label,
                accent = choice.warn ~= "safe" or choice.startsCombat,
                onClick = function()
                    send("choose", { index = choice.index })
                end,
            }
        end
    elseif view.phase == "outcome" and view.outcome then
        titleText = view.outcome.eventTitle or "Outcome"
        bodyText = view.outcome.text
        noteText = view.outcome.check
        if view.outcome.chips and #view.outcome.chips > 0 then
            chipText = table.concat(view.outcome.chips, "    ")
        end
        -- A fight resolves the year, so its result belongs on the year's card.
        if view.outcome.combat then
            local c = view.outcome.combat
            local tag = (c.result == "won" and "WON")
                or (c.result == "fled" and "LEFT IT ALIVE")
                or "LOST"
            local line = string.format("%s after %d rounds · %d/%d health",
                tag, c.rounds, c.health, c.healthMax)
            chipText = chipText and (line .. "    " .. chipText) or line
        end
        buttons[#buttons + 1] = {
            text = "Continue",
            accent = true,
            onClick = function()
                send("continue")
            end,
        }
    else
        titleText = string.format("Age %d", view.age)
        bodyText = view.quietLine or "A year passes. Press Age Up when you are ready to spend it."
        buttons[#buttons + 1] = {
            text = "Age Up",
            accent = false,
            onClick = function()
                send("ageUp")
            end,
        }
    end

    UiKit.label(card, {
        Text = titleText,
        Size = UDim2.new(1, 0, 0, 28),
        TextSize = 22,
    })

    local buttonArea = #buttons * 54 + 12
    local bodyHeight = -(46 + buttonArea + 40)

    UiKit.label(card, {
        Text = bodyText,
        Position = UDim2.new(0, 0, 0, 38),
        Size = UDim2.new(1, 0, 1, bodyHeight),
        TextSize = 17,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LineHeight = 1.1,
    })

    if chipText then
        UiKit.label(card, {
            Text = chipText,
            Position = UDim2.new(0, 0, 1, bodyHeight + 46),
            Size = UDim2.new(1, 0, 0, 24),
            Font = UiKit.FontNumber,
            TextSize = 15,
            TextColor3 = Theme.accent,
        })
    end

    if noteText then
        UiKit.label(card, {
            Text = noteText,
            Position = UDim2.new(0, 0, 1, bodyHeight + 70),
            Size = UDim2.new(1, 0, 0, 20),
            Font = UiKit.FontNumber,
            TextSize = 13,
            TextColor3 = Theme.textDim,
        })
    end

    -- Choices, anchored to the bottom of the card.
    choicesFrame.Position = UDim2.new(0, 0, 1, -buttonArea)
    choicesFrame.Size = UDim2.new(1, 0, 0, buttonArea)
    UiKit.clear(choicesFrame)
    UiKit.ensureStack(choicesFrame, 8)

    -- Never strand the player: if the view arrives with nothing to press, give
    -- them the button that moves the year on rather than a dead screen.
    if #buttons == 0 then
        buttons[#buttons + 1] = {
            text = (view.phase == "outcome") and "Continue" or "Age Up",
            accent = true,
            onClick = function()
                send((view.phase == "outcome") and "continue" or "ageUp")
            end,
        }
    end

    for index, info in ipairs(buttons) do
        UiKit.button(choicesFrame, {
            Text = info.text,
            Size = UDim2.new(1, 0, 0, 46),
            LayoutOrder = index,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = info.accent and Theme.panelAlt or Theme.panel,
            TextColor3 = Theme.text,
        }, info.onClick)
    end

    ageUpButton.Visible = view.phase == "play"
    ageUpButton.Active = view.phase == "play"
end

--- Character creation: the sheet is filled in before the life starts.
local function renderCreate(view)
    local create = view.create
    if not create then
        return
    end

    birthParagraph.Text = create.birthParagraph
    createInstruction.Text = create.instruction
    rerollButton.Text = string.format("Re-roll the sheet (%d left)", create.rerollsLeft)
    rerollButton.Active = create.rerollsLeft > 0

    UiKit.clear(createSheet)
    local order = 1

    -- Name
    local nameRow = UiKit.create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        LayoutOrder = order,
    }, createSheet)
    order += 1
    UiKit.label(nameRow, {
        Text = "NAME",
        Size = UDim2.new(0, 54, 1, 0),
        Font = UiKit.FontUi,
        TextSize = 12,
        TextColor3 = Theme.textDim,
    })
    local nameBox = UiKit.create("TextBox", {
        Text = create.name,
        Position = UDim2.new(0, 58, 0, 0),
        Size = UDim2.new(1, -58, 1, 0),
        BackgroundColor3 = Theme.panelAlt,
        BorderSizePixel = 0,
        Font = UiKit.FontUi,
        TextSize = 15,
        TextColor3 = Theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    }, nameRow)
    UiKit.create("UICorner", { CornerRadius = UDim.new(0, 4) }, nameBox)
    UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, nameBox)
    nameBox.FocusLost:Connect(function()
        send("setName", { name = nameBox.Text })
    end)

    sectionHeader(createSheet, order, "RACE")
    order += 1

    for _, race in ipairs(create.races) do
        local selected = create.selectedRace == race.id
        local lines = { race.name:upper() }
        for _, bonus in ipairs(race.bonuses) do
            table.insert(lines, bonus)
        end
        for _, extra in ipairs(race.extra) do
            table.insert(lines, extra)
        end
        UiKit.button(createSheet, {
            Text = table.concat(lines, "   ·   "),
            Size = UDim2.new(1, 0, 0, 46),
            LayoutOrder = order,
            TextSize = 13,
            TextWrapped = true,
            BackgroundColor3 = selected and Theme.accent or Theme.panelAlt,
            TextColor3 = selected and Color3.fromRGB(26, 22, 14) or Theme.text,
        }, function()
            send("selectRace", { race = race.id })
        end)
        order += 1

        UiKit.label(createSheet, {
            Text = race.blurb,
            Size = UDim2.new(1, 0, 0, 30),
            LayoutOrder = order,
            TextSize = 13,
            TextColor3 = Theme.textDim,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
        })
        order += 1
    end

    sectionHeader(createSheet, order, "THE SHEET AS ROLLED")
    order += 1
    for _, key in ipairs(Config.AttributeOrder) do
        local value = create.preview[key] or 0
        local base = create.baseRoll[key] or value
        attributeRow(createSheet, order, key, value, value - base)
        order += 1
    end

    local derived = create.previewDerived
    if derived then
        UiKit.label(createSheet, {
            Text = string.format(
                "HealthMax %d   ManaMax %d   Dodge %d%%   Crit %d%%   Fortune %d",
                derived.healthMax,
                derived.manaMax,
                derived.dodge,
                derived.crit,
                derived.fortune
            ),
            Size = UDim2.new(1, 0, 0, 34),
            LayoutOrder = order,
            Font = UiKit.FontNumber,
            TextSize = 13,
            TextColor3 = Theme.textDim,
            TextWrapped = true,
        })
        order += 1
    end

    beginButton.Active = create.selectedRace ~= nil
    beginButton.Text = create.selectedRace and "Begin this life" or "Choose a race to begin"

    -- Keep the name in the box framed as a noun/verb label row, then done.
    createFrame.Visible = true
end

local function renderDeath(view)
    local death = view.death
    if not death then
        return
    end
    UiKit.clear(deathPanel)

    UiKit.label(deathPanel, {
        Text = "THE LEDGER IS CLOSED",
        Size = UDim2.new(1, 0, 0, 22),
        Font = UiKit.FontUi,
        TextSize = 14,
        TextColor3 = Theme.accent,
    })

    UiKit.label(deathPanel, {
        Text = death.epitaph,
        Position = UDim2.new(0, 0, 0, 34),
        Size = UDim2.new(1, 0, 0, 120),
        TextSize = 19,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LineHeight = 1.12,
    })

    local leftColumn = UiKit.create("Frame", {
        Position = UDim2.new(0, 0, 0, 170),
        Size = UDim2.new(0.55, -10, 1, -230),
        BackgroundTransparency = 1,
    }, deathPanel)
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }, leftColumn)

    local order = 1
    for _, pair in ipairs(death.summary) do
        statRow(leftColumn, order, pair[1], pair[2])
        order += 1
    end

    local rightColumn = UiKit.create("Frame", {
        Position = UDim2.new(0.56, 0, 0, 170),
        Size = UDim2.new(0.44, 0, 1, -230),
        BackgroundTransparency = 1,
    }, deathPanel)
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }, rightColumn)

    local rightOrder = 1
    sectionHeader(rightColumn, rightOrder, "THE SHEET AT THE END")
    rightOrder += 1
    for _, key in ipairs(Config.AttributeOrder) do
        attributeRow(rightColumn, rightOrder, key, death.attrs[key] or 0)
        rightOrder += 1
    end

    if #death.notable > 0 then
        rightOrder += 1
        sectionHeader(rightColumn, rightOrder, "WHAT THEY DID")
        rightOrder += 1
        for _, clause in ipairs(death.notable) do
            UiKit.label(rightColumn, {
                Text = "· " .. clause,
                Size = UDim2.new(1, 0, 0, 28),
                LayoutOrder = rightOrder,
                TextSize = 13,
                TextColor3 = Theme.textDim,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
            })
            rightOrder += 1
        end
    end

    -- Rebuilt every render, because the panel above is cleared on each one.
    UiKit.button(deathPanel, {
        Name = "PlayAgain",
        Text = "Play again",
        Size = UDim2.new(0, 220, 0, 44),
        Position = UDim2.new(0, 0, 1, -44),
        BackgroundColor3 = Theme.accent,
        TextColor3 = Color3.fromRGB(26, 22, 14),
        TextSize = 18,
    }, function()
        send("playAgain")
    end)

    deathFrame.Visible = true
end

-- ===========================================================================
-- Combat (§6.2) — the tactical screen
--
-- Every number here arrives inside view.combat, computed on the server: the
-- projection on a button is the number the log will print. The client never
-- rolls a die, never moves health and never works out a hit — pressing a
-- button sends an intent and waits to be told what happened to it.
--
-- UI law (§6.1): the telegraph is the whole point of this screen. If something
-- is winding up, it says so, and it says what the blow will cost and what
-- Brace would save, BEFORE the player presses anything.
-- ===========================================================================

local combatFrame = UiKit.create("Frame", {
    Name = "Combat",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Theme.background,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 4,
}, root)

-- Selection is a view preference, not combat state: it only decides which
-- target id rides along with the next intent.
local selectedTargetId = nil
local inspectOpen = {}
local lastCombatView = nil
local renderCombat -- forward: the panels re-render themselves on a click

local function clearTargetIfDown(enemy)
    if enemy.downed or enemy.fled then
        if selectedTargetId == enemy.id then
            selectedTargetId = nil
        end
    end
end

--- A track and a filled fraction of it, drawn once at the given value.
local function fractionBar(parent, props, fraction, color)
    local track = UiKit.create("Frame", props, parent)
    UiKit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = UiKit.create("Frame", {
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Size = UDim2.new(math.clamp(fraction or 0, 0, 1), 0, 1, 0),
    }, track)
    UiKit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
    return track
end

local function statusLine(parent, chips, position, width)
    local text = "No conditions."
    if chips and #chips > 0 then
        local labels = {}
        for _, chip in ipairs(chips) do
            labels[#labels + 1] = chip.label
        end
        text = table.concat(labels, "  ·  ")
    end
    return UiKit.label(parent, {
        Text = text,
        Position = position,
        Size = UDim2.new(width, 0, 0, 18),
        TextSize = 13,
        Font = UiKit.FontNumber,
        TextColor3 = (chips and #chips > 0) and Theme.accent or Theme.textDim,
        TextWrapped = true,
    })
end

--- One enemy: name, health, the telegraph, its statuses, and the numbers the
--- player needs to pick an action (armour/ward/damage type).
local function renderEnemy(parent, enemy, order)
    clearTargetIfDown(enemy)
    local selected = selectedTargetId == enemy.id
    local panel = UiKit.panel(parent, {
        Name = "Enemy_" .. tostring(enemy.id),
        Size = UDim2.new(1, 0, 0, 190),
        LayoutOrder = order,
        BackgroundColor3 = enemy.downed and Theme.panel or (selected and Theme.panelAlt or Theme.panel),
    }, 12)
    if selected then
        UiKit.create("UIStroke", {
            Thickness = 2,
            Color = Theme.accent,
        }, panel)
    end

    local heading = string.format("%s", enemy.name)
    if enemy.downed then
        heading = heading .. "  — down"
    elseif enemy.fled then
        heading = heading .. "  — gone"
    end
    UiKit.label(panel, {
        Text = heading,
        Size = UDim2.new(1, -110, 0, 24),
        TextSize = 20,
    })
    UiKit.label(panel, {
        Text = enemy.archetype or "",
        Position = UDim2.new(1, -104, 0, 4),
        Size = UDim2.new(0, 104, 0, 18),
        TextSize = 12,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- Health, then the number itself: a bar the player has to guess at is decoration.
    fractionBar(panel, {
        Position = UDim2.new(0, 0, 0, 30),
        Size = UDim2.new(1, -70, 0, 10),
        BackgroundColor3 = Color3.fromRGB(12, 12, 15),
        BorderSizePixel = 0,
    }, enemy.healthFraction, Theme.healthFill)
    UiKit.label(panel, {
        Text = string.format("%d / %d", enemy.health, enemy.healthMax),
        Position = UDim2.new(1, -66, 0, 26),
        Size = UDim2.new(0, 66, 0, 18),
        TextSize = 14,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.text,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- THE TELEGRAPH. Loud on purpose: this is what the fight is played on.
    local y = 46
    if enemy.telegraph then
        local t = enemy.telegraph
        local strip = UiKit.panel(panel, {
            Position = UDim2.new(0, 0, 0, y),
            Size = UDim2.new(1, 0, 0, 44),
            BackgroundColor3 = Color3.fromRGB(52, 26, 24),
        }, 6)
        UiKit.label(strip, {
            Text = string.format("%s — %s", t.label, t.detail),
            Size = UDim2.new(1, 0, 0, 18),
            TextSize = 16,
            Font = Enum.Font.SourceSansBold,
            TextColor3 = Theme.bad,
        })
        local cost = "It will hit you."
        if t.incoming then
            cost = string.format(
                "Hits you for %d %s — %d if you Brace (saves %d).",
                t.incoming.youTake, string.upper(t.incoming.damageType),
                t.incoming.youTakeBraced, t.incoming.braceSaves
            )
        end
        UiKit.label(strip, {
            Text = cost,
            Position = UDim2.new(0, 0, 0, 20),
            Size = UDim2.new(1, 0, 0, 18),
            TextSize = 13,
            Font = UiKit.FontNumber,
            TextColor3 = Theme.text,
        })
        y = y + 50
    end

    statusLine(panel, enemy.statuses, UDim2.new(0, 0, 0, y), 1)

    UiKit.label(panel, {
        Text = string.format("ARM %d   WARD %d   %s   threat %d",
            enemy.armour, enemy.ward, string.upper(enemy.deals or ""), enemy.threat or 0),
        Position = UDim2.new(0, 0, 1, -20),
        Size = UDim2.new(1, -150, 0, 16),
        TextSize = 12,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
    })

    if not enemy.downed and not enemy.fled then
        UiKit.button(panel, {
            Text = selected and "Targeted" or "Target",
            Position = UDim2.new(1, -96, 1, -38),
            Size = UDim2.new(0, 96, 0, 26),
            TextSize = 13,
            BackgroundColor3 = selected and Theme.accent or Theme.panelAlt,
            TextColor3 = selected and Color3.fromRGB(26, 22, 14) or Theme.text,
        }, function()
            selectedTargetId = enemy.id
            renderCombat(lastCombatView)
        end)
    end

    if enemy.note then
        UiKit.button(panel, {
            Text = inspectOpen[enemy.id] and "Hide" or "Inspect",
            Position = UDim2.new(1, -96, 0, 26),
            Size = UDim2.new(0, 96, 0, 22),
            TextSize = 12,
            BackgroundColor3 = Theme.panel,
        }, function()
            inspectOpen[enemy.id] = not inspectOpen[enemy.id]
            renderCombat(lastCombatView)
        end)
        if inspectOpen[enemy.id] then
            UiKit.label(panel, {
                Text = enemy.note,
                Position = UDim2.new(0, 0, 0, 120),
                Size = UDim2.new(1, -110, 0, 40),
                TextSize = 13,
                TextColor3 = Theme.textDim,
                TextWrapped = true,
            })
        end
    end
end

--- The action list. Each row carries its own cost and its own projected
--- damage, so the player never has to guess what a button does.
local function renderAction(parent, action, order, canAct)
    local usable = action.enabled and canAct
    local text = string.format("%s.  %s", action.key, action.label)
    if action.cost and action.cost ~= "" then
        text = string.format("%s   (%s)", text, action.cost)
    end
    if action.detail and action.detail ~= "" then
        text = string.format("%s\n%s", text, action.detail)
    end
    if not usable and action.reason then
        text = string.format("%s\nunavailable: %s", text, tostring(action.reason))
    end
    UiKit.button(parent, {
        Text = text,
        Size = UDim2.new(1, 0, 0, 46),
        LayoutOrder = order,
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BackgroundColor3 = usable and Theme.panelAlt or Theme.panel,
        TextColor3 = usable and Theme.text or Theme.textDim,
    }, function()
        if not usable then
            return
        end
        send("combatAction", { action = action.id, target = selectedTargetId })
    end)
end

function renderCombat(view)
    local combat = view and view.combat
    if not combat then
        return
    end
    lastCombatView = view
    UiKit.clear(combatFrame)

    local canAct = combat.awaitingAction and true or false

    UiKit.label(combatFrame, {
        Text = combat.title,
        Position = UDim2.new(0, 24, 0, 12),
        Size = UDim2.new(1, -340, 0, 30),
        TextSize = 26,
    })
    UiKit.label(combatFrame, {
        Text = string.format("%s    %s", combat.roundLabel, combat.order),
        Position = UDim2.new(1, -320, 0, 18),
        Size = UDim2.new(0, 296, 0, 20),
        TextSize = 14,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- The one line that keeps the tactical loop honest across the whole panel.
    local winding = nil
    for _, enemy in ipairs(combat.enemies) do
        if enemy.telegraph then
            winding = enemy
            break
        end
    end
    if winding then
        local t = winding.telegraph
        local message = string.format(
            "%s IS WINDING UP — %s lands %s.",
            string.upper(winding.name), t.label, t.detail
        )
        if t.incoming then
            message = string.format("%s  Brace now: %d instead of %d.",
                message, t.incoming.youTakeBraced, t.incoming.youTake)
        end
        UiKit.label(combatFrame, {
            Text = message,
            Position = UDim2.new(0, 24, 0, 48),
            Size = UDim2.new(1, -48, 0, 22),
            TextSize = 16,
            Font = Enum.Font.SourceSansBold,
            TextColor3 = Theme.bad,
        })
    end

    -- ---------------------------------------------------------------- enemies
    local enemyColumn = UiKit.create("ScrollingFrame", {
        Name = "Enemies",
        Position = UDim2.new(0, 24, 0, 82),
        Size = UDim2.new(1, -560, 1, -106),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, combatFrame)
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, enemyColumn)
    local order = 1
    for _, enemy in ipairs(combat.enemies) do
        renderEnemy(enemyColumn, enemy, order)
        order += 1
    end

    -- ---------------------------------------------------------------- player
    local right = UiKit.create("Frame", {
        Name = "PlayerSide",
        Position = UDim2.new(1, -512, 0, 82),
        Size = UDim2.new(0, 488, 1, -106),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, combatFrame)

    local panel = UiKit.panel(right, {
        Size = UDim2.new(1, 0, 0, 172),
    }, 12)
    UiKit.label(panel, {
        Text = string.format("%s   ·   level %d %s", combat.player.name, combat.player.level,
            combat.player.vocation or ""),
        Size = UDim2.new(1, -110, 0, 22),
        TextSize = 18,
    })
    if combat.player.wounded then
        UiKit.label(panel, {
            Text = "WOUNDED −25% DEALT",
            Position = UDim2.new(1, -120, 0, 2),
            Size = UDim2.new(0, 120, 0, 18),
            TextSize = 13,
            Font = UiKit.FontNumber,
            TextColor3 = Theme.bad,
            TextXAlignment = Enum.TextXAlignment.Right,
        })
    end

    fractionBar(panel, {
        Position = UDim2.new(0, 0, 0, 28),
        Size = UDim2.new(1, -90, 0, 12),
        BackgroundColor3 = Color3.fromRGB(12, 12, 15),
        BorderSizePixel = 0,
    }, combat.player.healthFraction, Theme.healthFill)
    UiKit.label(panel, {
        Text = string.format("%d / %d", combat.player.health, combat.player.healthMax),
        Position = UDim2.new(1, -86, 0, 24),
        Size = UDim2.new(0, 86, 0, 18),
        TextSize = 14,
        Font = UiKit.FontNumber,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    fractionBar(panel, {
        Position = UDim2.new(0, 0, 0, 48),
        Size = UDim2.new(1, -90, 0, 8),
        BackgroundColor3 = Color3.fromRGB(12, 12, 15),
        BorderSizePixel = 0,
    }, combat.player.manaMax > 0 and (combat.player.mana / combat.player.manaMax) or 0, Theme.expFill)
    UiKit.label(panel, {
        Text = string.format("%d / %d mana  (+%d a round)", combat.player.mana,
            combat.player.manaMax, combat.player.manaRegen or 0),
        Position = UDim2.new(0, 0, 0, 58),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 13,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
    })

    statusLine(panel, combat.player.statuses, UDim2.new(0, 0, 0, 80), 1)
    UiKit.label(panel, {
        Text = string.format("ARM %d   WARD %d   crit %d%%   dodge %d%%   %s",
            combat.player.armour, combat.player.ward, combat.player.crit, combat.player.dodge,
            combat.player.weapon or "unarmed"),
        Position = UDim2.new(0, 0, 0, 104),
        Size = UDim2.new(1, 0, 0, 16),
        TextSize = 12,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
    })
    if combat.warning then
        UiKit.label(panel, {
            Text = combat.warning,
            Position = UDim2.new(0, 0, 0, 124),
            Size = UDim2.new(1, 0, 0, 38),
            TextSize = 12,
            TextColor3 = Theme.textDim,
            TextWrapped = true,
        })
    end

    -- ---------------------------------------------------------------- actions
    UiKit.label(right, {
        Text = canAct and "ACTIONS" or "WAITING",
        Position = UDim2.new(0, 0, 0, 180),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 13,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
    })
    local actionArea = UiKit.create("ScrollingFrame", {
        Name = "Actions",
        Position = UDim2.new(0, 0, 0, 202),
        Size = UDim2.new(1, 0, 1, -202 - 178),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, right)
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, actionArea)

    local actionOrder = 1
    for _, action in ipairs(combat.actions) do
        renderAction(actionArea, action, actionOrder, canAct)
        actionOrder += 1
    end

    -- Fortune is a per-fight resource and never an action (§1.2), so it sits
    -- apart from the turn list.
    if combat.player.fortune and combat.player.fortune > 0 or combat.player.fortuneArmed then
        UiKit.button(actionArea, {
            Text = combat.player.fortuneArmed
                and "FORTUNE — armed. The next die rolled against you is rerolled."
                or string.format("FORTUNE (%d left) — reroll the next die rolled against you. Not a turn.",
                    combat.player.fortune or 0),
            Size = UDim2.new(1, 0, 0, 34),
            LayoutOrder = actionOrder,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = combat.player.fortuneArmed and Theme.accent or Theme.panel,
            TextColor3 = combat.player.fortuneArmed and Color3.fromRGB(26, 22, 14) or Theme.accent,
        }, function()
            if combat.player.fortuneArmed then
                return
            end
            send("combatAction", { action = "fortune" })
        end)
    end

    -- ------------------------------------------------------------------- log
    local logPanel = UiKit.panel(right, {
        Name = "Log",
        Position = UDim2.new(0, 0, 1, -170),
        Size = UDim2.new(1, 0, 0, 170),
    }, 10)
    UiKit.label(logPanel, {
        Text = "WHAT JUST HAPPENED",
        Size = UDim2.new(1, 0, 0, 14),
        TextSize = 11,
        Font = UiKit.FontNumber,
        TextColor3 = Theme.textDim,
    })
    local logList = UiKit.create("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 16),
        Size = UDim2.new(1, 0, 1, -16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, logPanel)
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
    }, logList)
    local logOrder = 1
    for _, line in ipairs(combat.log or {}) do
        local dim = string.sub(line, 1, 4) == "    "
        UiKit.label(logList, {
            Text = line,
            Size = UDim2.new(1, -8, 0, 15),
            LayoutOrder = logOrder,
            TextSize = 12,
            Font = UiKit.FontNumber,
            TextColor3 = dim and Theme.textDim or Theme.text,
        })
        logOrder += 1
    end
end

-- ===========================================================================
-- One render function, driven entirely by the server's view model
-- ===========================================================================

local function render(view)
    local creating = view.phase == "create"
    local dead = view.phase == "dead"
    local fighting = view.phase == "combat" and view.combat ~= nil

    createFrame.Visible = creating
    deathFrame.Visible = dead
    combatFrame.Visible = fighting

    topBar.Visible = not creating
    rail.Visible = not fighting
    card.Visible = not creating and not dead and not fighting
    ageUpButton.Visible = not creating and not dead and not fighting

    if creating then
        renderCreate(view)
    elseif dead then
        renderTopBar(view)
        renderRail(view)
        renderDeath(view)
    elseif fighting then
        -- The fight owns the screen: no rail, no event card, no Age Up while
        -- there is something in the cellar waiting to take its turn.
        renderTopBar(view)
        renderCombat(view)
    else
        renderTopBar(view)
        renderRail(view)
        renderCard(view)
    end
end

-- A render that throws used to leave a half-drawn screen and then fail again on
-- every later update: the player sees one card and the game stops answering.
-- Show the failure instead, so a stuck screen says why it is stuck.
local function safeRender(view)
    local ok, err = pcall(render, view)
    if ok then
        return
    end
    warn("[NewWorldLife] render failed: " .. tostring(err))
    pcall(function()
        UiKit.clear(card)
        UiKit.label(card, {
            Text = "RENDER ERROR\n\n" .. tostring(err),
            Size = UDim2.new(1, 0, 0, 160),
            TextSize = 15,
            TextWrapped = true,
            TextColor3 = Theme.bad,
        })
    end)
end

updateRemote.OnClientEvent:Connect(safeRender)
