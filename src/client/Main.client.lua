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
UiKit.create("UIPadding", { PaddingLeft = UDim.new(0, 18) }, topBar)

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
-- a run without a choice.
local healthBlock = UiKit.create("Frame", {
    Size = UDim2.new(0, 190, 0, 36),
    BackgroundTransparency = 1,
    LayoutOrder = 2,
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

local ageValue = topStat("AGE", 54, 1)
local levelValue = topStat("LEVEL · EXP", 118, 3)
local coinValue = topStat("COIN", 74, 4)
local karmaValue = topStat("KARMA", 74, 5)
local notorietyValue = topStat("NOTORIETY", 84, 6)
local yearValue = UiKit.label(topBar, {
    Text = "",
    Size = UDim2.new(0, 320, 0, 20),
    LayoutOrder = 7,
    Font = UiKit.FontProse,
    TextSize = 14,
    TextColor3 = Theme.textDim,
    TextXAlignment = Enum.TextXAlignment.Right,
})

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
        for _, choice in ipairs(view.event.choices) do
            local label = choice.label
            if choice.warn and choice.warn ~= "safe" then
                label = string.format("%s   %s", choice.label, choice.warn)
            end
            buttons[#buttons + 1] = {
                text = label,
                accent = choice.warn ~= "safe",
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
    UiKit.create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, choicesFrame)

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
-- One render function, driven entirely by the server's view model
-- ===========================================================================

local function render(view)
    local creating = view.phase == "create"
    local dead = view.phase == "dead"

    createFrame.Visible = creating
    deathFrame.Visible = dead

    topBar.Visible = not creating
    rail.Visible = true
    card.Visible = not creating and not dead
    ageUpButton.Visible = not creating and not dead

    if creating then
        renderCreate(view)
    elseif dead then
        renderTopBar(view)
        renderRail(view)
        renderDeath(view)
    else
        renderTopBar(view)
        renderRail(view)
        renderCard(view)
    end
end

updateRemote.OnClientEvent:Connect(render)
