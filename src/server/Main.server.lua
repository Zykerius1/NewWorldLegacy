--[[
    Main — the server entry point.

    Responsibilities, deliberately few:
      * create the two RemoteEvents the client uses,
      * hold one GameState per player,
      * turn an intent from the client into a call on that GameState,
      * push the resulting view model back,
      * clean up on leave.

    The client sends INTENTS ("ageUp", "choose 2"). It never sends outcomes and
    it never mutates its own numbers: every value it displays came from here.
    One player per server is fine for a single-player game, but sessions are
    keyed by player anyway so a second joiner cannot corrupt the first.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- This game is a screen, not a body. There is no avatar, no walkable world and
-- no place for one to stand: left to itself Roblox spawns a character in empty
-- space, drops it, drains its health bar, plays the death sound and respawns —
-- a whoosh and an emptying bar on a loop, forever. Nobody needs a character, so
-- nobody gets one.
Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rng = require(Shared.Rng)
local GameState = require(script.Parent.GameState)

-- ===========================================================================
-- Remotes
-- ===========================================================================

local function ensureRemote(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing then
        return existing
    end
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local actionRemote = ensureRemote(Config.Remotes.action)
local updateRemote = ensureRemote(Config.Remotes.update)

-- ===========================================================================
-- Sessions
-- ===========================================================================

local sessions = {}

local function pushState(player)
    local session = sessions[player]
    if not session then
        return
    end
    updateRemote:FireClient(player, session.state:view())
end

local function newSession(player)
    return {
        state = GameState.new(Rng.new()),
        player = player,
    }
end

--- Route one intent. Returns true if the state changed and needs pushing.
local function handleIntent(player, action, data)
    local session = sessions[player]
    if not session then
        return false
    end
    local state = session.state
    if not GameState.Intents[action] then
        warn(string.format("[NWL] rejected unknown intent %q from %s", tostring(action), player.Name))
        return false
    end

    if action == "selectRace" then
        state:setRace(type(data) == "table" and data.race or nil)
    elseif action == "setName" then
        state:setName(type(data) == "table" and data.name or nil)
    elseif action == "reroll" then
        state:reroll()
    elseif action == "begin" then
        state:begin()
    elseif action == "ageUp" then
        state:ageUp()
    elseif action == "choose" then
            local index = type(data) == "table" and tonumber(data.index) or nil
            state:choose(index)
    elseif action == "combatAction" then
            -- The client sends which button, never a result. The engine is
            -- the only thing that rolls dice or moves health.
            local payload = type(data) == "table" and data or {}
            local okAction, reason = state:combatAction({
                    action = payload.action,
                    target = payload.target,
            })
            if not okAction then
                    warn(string.format("[NWL] combat intent %q refused: %s",
                            tostring(payload.action), tostring(reason)))
                    return false
            end
    elseif action == "continue" then
        state:continue()
    elseif action == "playAgain" then
        state:reset()
    end

    return true
end

actionRemote.OnServerEvent:Connect(function(player, action, data)
    local ok, err = pcall(handleIntent, player, action, data)
    if not ok then
        warn(string.format("[NWL] intent %q failed: %s", tostring(action), tostring(err)))
    end
    pushState(player)
end)

local function onPlayerAdded(player)
    sessions[player] = newSession(player)
    pushState(player)
end

local function onPlayerRemoving(player)
    sessions[player] = nil -- clean up: no persistence in step 1
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

print("[New World Life] server ready — loop skeleton (step 1)")
