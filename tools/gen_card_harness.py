#!/usr/bin/env python3
"""Card harness — renders every event card through the real client UI code.

The bug this exists for: an event card drew its title and body but no buttons at
all. The client builds the whole interface with Instance.new, and Studio is not
available here, so this harness supplies a stub Roblox instance model, runs the
real `src/client/Main.client.lua` against it, and then pushes a real view model
for every event in `Events` through the client's update handler.

For each card it asserts the thing a player needs: at least one TextButton that
is a descendant of the card, is not hidden by any ancestor's Visible, and
resolves to a non-zero absolute size.

Run:
    python3 tools/gen_card_harness.py                 # writes /tmp/card_harness.luau
    /home/team/shared/tools/bin/luau /tmp/card_harness.luau

Exit code is non-zero (luau errors) if any card renders without a pressable
button, so it can gate a merge.

Limits, stated honestly: this is a stub, not Roblox. It ignores UIPadding,
UIListLayout and text measurement when working out absolute size, so a button
can pass here and still be cramped or overlapped on a real screen. It does not
prove the buttons are clickable, only that they exist, are parented into the
card, are visible, and have a size.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODS = [
    ("Config", "src/shared/Config.lua"),
    ("Rng", "src/shared/Rng.lua"),
    ("Types", "src/shared/Types.lua"),
    ("CombatData", "src/shared/CombatData.lua"),
    ("Combat", "src/shared/Combat.lua"),
    ("Attributes", "src/shared/Attributes.lua"),
    ("Events", "src/shared/Events.lua"),
    ("GameState", "src/server/GameState.lua"),
    ("UiKit", "src/client/UiKit.lua"),
]

MAIN = "src/client/Main.client.lua"

PREAMBLE = r'''
-- ==== stub Roblox environment ====
-- Everything below stands in for the engine so the real client script can run
-- here: instances, the services it asks for, Enum, UDim2/Color3, task, require.

local __realprint = print

warn = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  __realprint("[warn] " .. table.concat(parts, " "))
end

-- A seeded generator, so a run is repeatable. It is an LCG, not Roblox's, so
-- numbers will not match Studio; the harness only needs a plausible life.
Random = {}
function Random.new(seed)
  local s = math.floor(math.abs(seed or 12345)) % 2147483647
  if s < 1 then s = 1 end
  local obj = {}
  local function step()
    s = (s * 1103515245 + 12345) % 2147483648
    return s
  end
  function obj:NextInteger(a, b) return a + (step() % (b - a + 1)) end
  function obj:NextNumber() return step() / 2147483648 end
  return obj
end

UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }

UDim2 = {
  new = function(xs, xo, ys, yo)
    return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
  end,
  fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end,
  fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end,
}
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Color3 = {
  fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
  new = function(r, g, b) return { R = r, G = g, B = b } end,
}

-- Any Enum.X.Y resolves to a token; the stub never compares them.
Enum = setmetatable({}, {
  __index = function(_, group)
    return setmetatable({}, {
      __index = function(_, item) return group .. "." .. item end,
    })
  end,
})

task = {
  spawn = function(fn, ...) fn(...) end,
  defer = function(fn, ...) fn(...) end,
  wait = function() end,
}

-- ==== stub instances ====

local DEFAULTS = {
  Visible = true,
  Name = "",
  Text = "",
  TextSize = 14,
  BackgroundTransparency = 0,
  Size = UDim2.new(0, 0, 0, 0),
  Position = UDim2.new(0, 0, 0, 0),
  Active = true,
  AutoButtonColor = true,
}

local SIGNALS = {
  OnClientEvent = true,
  Activated = true,
  MouseButton1Click = true,
  FocusLost = true,
  CharacterAdded = true,
}

local SUPER = {
  TextButton = { "GuiButton", "GuiObject" },
  TextLabel = { "GuiObject" },
  Frame = { "GuiObject" },
  ScrollingFrame = { "GuiObject" },
  ScreenGui = { "LayerCollector" },
  Folder = {},
  RemoteEvent = {},
}

local METHODS = {}

local function makeSignal(handlers)
  return {
    Connect = function(_, fn)
      table.insert(handlers, fn)
      return { Disconnect = function() end }
    end,
    Once = function(_, fn) table.insert(handlers, fn) end,
    Fire = function(_, ...)
      for _, fn in ipairs(handlers) do fn(...) end
    end,
  }
end

local function signalFor(self, name)
  local signals = rawget(self, "_signals")
  if not signals[name] then signals[name] = makeSignal({}) end
  return signals[name]
end

local meta = {}

meta.__index = function(self, key)
  if key == "ClassName" then return rawget(self, "_className") end
  local method = METHODS[key]
  if method then return method end
  if SIGNALS[key] then return signalFor(self, key) end
  local props = rawget(self, "_props")
  if props[key] ~= nil then return props[key] end
  return DEFAULTS[key]
end

meta.__newindex = function(self, key, value)
  if key == "Parent" then
    if rawget(self, "_destroyed") then
      error(string.format("The Parent property of %s is locked, current parent: NULL", rawget(self, "_className")))
    end
    local old = rawget(self, "_parent")
    if old then
      local siblings = rawget(old, "_children")
      for i, child in ipairs(siblings) do
        if child == self then
          table.remove(siblings, i)
          break
        end
      end
    end
    rawset(self, "_parent", value)
    if value then
      table.insert(rawget(value, "_children"), self)
    end
    return
  end
  rawget(self, "_props")[key] = value
end

function METHODS.GetChildren(self)
  local out = {}
  for i, child in ipairs(rawget(self, "_children")) do out[i] = child end
  return out
end

function METHODS.GetDescendants(self)
  local out = {}
  local function walk(node)
    for _, child in ipairs(rawget(node, "_children")) do
      table.insert(out, child)
      walk(child)
    end
  end
  walk(self)
  return out
end

function METHODS.IsA(self, className)
  local own = rawget(self, "_className")
  if own == className then return true end
  for _, super in ipairs(SUPER[own] or {}) do
    if super == className then return true end
  end
  return false
end

function METHODS.FindFirstChild(self, name)
  for _, child in ipairs(rawget(self, "_children")) do
    if child.Name == name then return child end
  end
  return nil
end

function METHODS.WaitForChild(self, name)
  local found = METHODS.FindFirstChild(self, name)
  if not found then
    error("harness: WaitForChild(" .. tostring(name) .. ") not provided on " .. tostring(rawget(self, "_className")))
  end
  return found
end

function METHODS.IsDescendantOf(self, ancestor)
  local node = rawget(self, "_parent")
  while node do
    if node == ancestor then return true end
    node = rawget(node, "_parent")
  end
  return false
end

function METHODS.Destroy(self)
  if rawget(self, "_destroyed") then return end
  rawset(self, "_destroyed", true)
  for _, child in ipairs(METHODS.GetChildren(self)) do
    METHODS.Destroy(child)
  end
  local parent = rawget(self, "_parent")
  if parent then
    local siblings = rawget(parent, "_children")
    for i, child in ipairs(siblings) do
      if child == self then
        table.remove(siblings, i)
        break
      end
    end
  end
  rawset(self, "_parent", nil)
end

function METHODS.FireServer() end

-- Harness-only: hang a plain Lua table (a module proxy) off a stub instance so
-- WaitForChild can find it by name.
function __adopt(parent, child)
  table.insert(rawget(parent, "_children"), child)
  rawset(child, "_parent", parent)
end

Instance = {
  new = function(className)
    return setmetatable({
      _className = className,
      _props = {},
      _children = {},
      _signals = {},
      _parent = nil,
      _destroyed = false,
    }, meta)
  end,
}
'''

ENV = r'''
-- ==== the services the client asks for ====
local Config = __req("Config")

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

local player = Instance.new("Folder")
player.Name = "LocalPlayer"
playerGui.Parent = player

local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = Config.Remotes.action

local updateRemote = Instance.new("RemoteEvent")
updateRemote.Name = Config.Remotes.update

local shared = setmetatable({}, {
  __index = function(_, key) return { __module = key } end,
})
shared.Name = "Shared"

local replicatedStorage = Instance.new("Folder")
replicatedStorage.Name = "ReplicatedStorage"
__adopt(replicatedStorage, shared)
actionRemote.Parent = replicatedStorage
updateRemote.Parent = replicatedStorage

local starterGui = {
  SetCoreGuiEnabled = function() end,
}

game = {
  GetService = function(_, name)
    if name == "Players" then return { LocalPlayer = player } end
    if name == "ReplicatedStorage" then return replicatedStorage end
    if name == "StarterGui" then return starterGui end
    error("harness: unexpected service " .. tostring(name))
  end,
}

script = {
  Parent = setmetatable({}, {
    __index = function(_, key) return { __module = key } end,
  }),
}

require = function(target)
  if type(target) == "table" and target.__module then return __req(target.__module) end
  error("harness: require() given something it cannot resolve")
end
'''

DRIVER = r'''
-- ==== render every event card, then look for a button ====
local Events = __req("Events")
local GameState = __req("GameState")
local Rng = __req("Rng")
local Config = __req("Config")

local VIEWPORT_W, VIEWPORT_H = 1920, 1080

local function absSize(instance)
  local chain = {}
  local node = instance
  while node do
    table.insert(chain, 1, node)
    node = node.Parent
  end
  local w, h = VIEWPORT_W, VIEWPORT_H
  for i = 2, #chain do
    local size = chain[i].Size
    w = w * size.X.Scale + size.X.Offset
    h = h * size.Y.Scale + size.Y.Offset
  end
  return w, h
end

local function hiddenByAncestor(instance)
  local node = instance
  while node do
    if node.Visible == false then return true end
    node = node.Parent
  end
  return false
end

local function findCard(screen)
  for _, descendant in ipairs(screen:GetDescendants()) do
    if descendant.Name == "Card" then return descendant end
  end
  return nil
end

local function findRenderError(screen)
  for _, descendant in ipairs(screen:GetDescendants()) do
    if descendant.ClassName == "TextLabel" and type(descendant.Text) == "string"
      and string.sub(descendant.Text, 1, 12) == "RENDER ERROR" then
      return descendant.Text
    end
  end
  return nil
end

local function pressableButtonsIn(card)
  local good, bad = {}, {}
  for _, descendant in ipairs(card:GetDescendants()) do
    if descendant.ClassName == "TextButton" then
      local w, h = absSize(descendant)
      local hidden = hiddenByAncestor(descendant)
      if not hidden and w > 0 and h > 0 then
        table.insert(good, { text = descendant.Text, w = w, h = h })
      else
        table.insert(bad, {
          text = descendant.Text,
          w = w,
          h = h,
          hidden = hidden,
        })
      end
    end
  end
  return good, bad
end

-- A card whose buttons are parented somewhere outside it: exactly the shape of
-- the bug this harness exists for (the choices frame destroyed by clear(card)).
local function strandedButtons(screen, card)
  local stranded = {}
  for _, descendant in ipairs(screen:GetDescendants()) do
    if descendant.ClassName == "TextButton" and not descendant:IsDescendantOf(card) then
      table.insert(stranded, descendant.Text)
    end
  end
  return stranded
end

local function newState(race, seed)
  local st = GameState.new(Rng.new(seed))
  st:setRace(race)
  st:setName("Hesta")
  st:begin()
  local guard = 0
  while st.alive and st.age < 6 and guard < 200 do
    guard += 1
    if st.phase == "play" then
      st:ageUp()
    elseif st.phase == "outcome" then
      st:continue()
    elseif st.phase == "event" then
      st:choose(1)
    else
      break
    end
  end
  return st
end

local screen
for _, descendant in ipairs(playerGui:GetChildren()) do
  if descendant.Name == "NewWorldLife" then screen = descendant end
end
if not screen then
  error("harness: the client never built its ScreenGui")
end

local state = newState("human", 4242)

local rendered, failures = 0, {}

local function check(label, view, expected)
  updateRemote.OnClientEvent:Fire(view)
  rendered += 1

  local err = findRenderError(screen)
  local card = findCard(screen)
  if not card then
    table.insert(failures, { label = label, reason = "no Card frame on screen" })
    return
  end
  local good, bad = pressableButtonsIn(card)
  if #good == 0 then
    local reason
    if err then
      reason = "render threw: " .. err
    else
      local stranded = strandedButtons(screen, card)
      local anywhere = 0
      for _, descendant in ipairs(screen:GetDescendants()) do
        if descendant.ClassName == "TextButton" then anywhere += 1 end
      end
      reason = string.format(
        "%d choice(s) expected, 0 pressable inside the card (%d inside but hidden/zero-size); %d button(s) exist anywhere on screen, %d of them outside the card",
        expected, #bad, anywhere, #stranded)
      if #stranded > 0 then
        reason = reason .. " — outside: " .. table.concat(stranded, " / ")
      end
    end
    table.insert(failures, { label = label, reason = reason })
  elseif #good < expected then
    table.insert(failures, {
      label = label,
      reason = string.format("%d pressable button(s) inside the card, expected %d", #good, expected),
    })
  end
end

local seen = {}
local function checkEvent(event)
  if seen[event.id] then return end
  seen[event.id] = true
  state.pendingEvent = event
  state.phase = "event"
  check("event " .. tostring(event.id), state:view(), #event.choices)
end

for _, event in ipairs(Events.All) do checkEvent(event) end
for _, event in ipairs(Events.Repeatable) do checkEvent(event) end

-- The same renderCard path, with no event: a quiet year and an outcome.
state.pendingEvent = nil
state.phase = "play"
check("quiet year", state:view(), 1)

state.phase = "outcome"
state.outcome = {
  eventTitle = "The Bread Cut Thin",
  text = "Nobody says anything about the board.",
  chips = { "WIS +1" },
}
check("outcome", state:view(), 1)

__realprint("")
__realprint("=============== CARD BUTTON HARNESS ===============")
__realprint(string.format("cards rendered: %d   events: %d", rendered, #Events.All + #Events.Repeatable))
if #failures == 0 then
  __realprint("PASS: every card has a visible, non-zero button inside it.")
else
  __realprint(string.format("FAIL: %d card(s) with nothing to press", #failures))
  for _, failure in ipairs(failures) do
    __realprint("  " .. failure.label .. " — " .. failure.reason)
  end
  error(string.format("%d card(s) rendered with no pressable button", #failures))
end
'''


def build():
    out = [PREAMBLE]
    out.append('''
-- ==== module registry ====
local __mods = {}
local __cache = {}
function __req(name)
  if __mods[name] == nil then error("missing module: " .. tostring(name)) end
  if __cache[name] == nil then __cache[name] = __mods[name]() end
  return __cache[name]
end
''')
    for name, rel in MODS:
        with open(os.path.join(ROOT, rel)) as handle:
            src = handle.read()
        out.append('\n__mods["%s"] = function()\n' % name)
        out.append(src)
        out.append("\nend\n")

    out.append(ENV)

    with open(os.path.join(ROOT, MAIN)) as handle:
        main_src = handle.read()
    out.append('\n-- ==== the real client script ====\n__mods["Main"] = function()\n')
    out.append(main_src)
    out.append("\nend\n__mods[\"Main\"]()\n")

    out.append(DRIVER)

    path = "/tmp/card_harness.luau"
    with open(path, "w") as handle:
        handle.write("".join(out))
    return path


if __name__ == "__main__":
    path = build()
    print("card harness written:", path)
