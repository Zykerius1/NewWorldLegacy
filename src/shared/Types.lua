--[[
    Types — shared type definitions for the life-sim state machine.

    Rojo maps every plain .lua file to a ModuleScript, so this module returns a
    table as well: the SCHEMA table below is the runtime description of the
    state, and is what GameState validates against when it applies deltas.
    The `export type` blocks above it are the compile-time description.

    Step 2 (combat) adds to these; it does not replace them.
]]

--!nonstrict

--[[
    export type AttrKey = "STR" | "VIT" | "INT" | "WIS" | "PIE" | "DEX" | "LUK" | "CHA"

    export type Attrs = { [string]: number }

    export type Deltas = {
        health: number?,
        healthMaxAdjust: number?,
        exp: number?,
        coin: number?,
        karma: number?,
        notoriety: number?,
        attr: { [string]: number }?,
        flags: { string }?,
        clearFlags: { string }?,
    }

    export type Choice = {
        label: string,
        warn: string?,
        text: string?,
        deltas: Deltas?,
        check: { attr: string, dc: number }?,
        success: { text: string, deltas: Deltas? }?,
        failure: { text: string, deltas: Deltas? }?,
        next: string?,
        delayYears: number?,
    }

    export type Event = {
        id: string,
        title: string,
        stage: string,
        ageMin: number?,
        ageMax: number?,
        weight: number?,
        chainOnly: boolean?,
        -- true = the generic/texture tier: can fire again later in the same run,
        -- but not within `cooldown` years of the last time it fired.
        repeatable: boolean?,
        cooldown: number?,
        requires: {
            race: { string }?,
            flags: { string }?,
            notFlags: { string }?,
            minStat: { [string]: number }?,
            maxStat: { [string]: number }?,
        }?,
        text: string,
        choices: { Choice },
    }

    export type Phase = "create" | "play" | "event" | "outcome" | "dead"

    export type State = {
        phase: Phase,
        name: string,
        raceKey: string?,
        age: number,
        attrs: Attrs?,
        health: number,
        healthMaxAdjust: number,
        mana: number,
        level: number,
        exp: number,
        coin: number,
        karma: number,
        notoriety: number,
        flags: { [string]: boolean },
        fired: { [string]: boolean },
        -- age each repeatable last fired at, for the cooldown gate
        firedAt: { [string]: number },
        chainQueue: { { id: string, atAge: number } },
        notable: { string },
        history: { string },
        lifespan: number?,
        alive: boolean,
        deathCause: string?,
    }
]]

local Types = {}

-- The runtime schema: which delta keys GameState knows how to apply.
Types.DeltaKeys = {
    "health",
    "healthMaxAdjust",
    "exp",
    "coin",
    "karma",
    "notoriety",
    "level",
}

-- Resource keys, in display order.
Types.ResourceOrder = { "health", "mana", "level", "exp", "coin", "karma", "notoriety" }

-- Phases of the loop.
Types.Phases = { "create", "play", "event", "outcome", "dead" }

-- Intents the client is allowed to send. Anything else is rejected, because
-- the client sends intents and never outcomes.
Types.Intents = {
    selectRace = true,
    setName = true,
    reroll = true,
    begin = true,
    ageUp = true,
    choose = true,
    combatAction = true,
    continue = true,
    playAgain = true,
}

return Types
