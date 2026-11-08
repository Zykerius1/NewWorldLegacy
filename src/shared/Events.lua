--[[
    Events — the event data and the draw.

    One event is one table. No scripting, no conditionals in prose: everything
    an event needs to know is in `requires`, and everything it does is in
    `deltas`. Content can therefore be authored by someone who is not a
    programmer (design brief §4.1).

    Shape:

        Event = {
            id        = "E02_DOG",         -- stable, never reused
            title     = "The Dog",
            stage     = "childhood",       -- UI styling + pool grouping
            ageMin    = 4, ageMax = 6,     -- inclusive
            weight    = 12,                -- base draw weight
            chainOnly = false,             -- true = only fires from a chain queue
            repeatable= false,             -- true = the generic tier (Events.Repeatable)
            cooldown  = 4,                 -- years before a repeatable may return
            requires  = {                  -- ALL must pass or it is not in the pool
                race      = { "human", "dwarf", "elf" },  -- omit = any
                flags     = { "family_poor" },
                notFlags  = { "met_dog" },
                minStat   = { health = 1 },               -- attr key or resource
                maxStat   = { notoriety = 0 },
            },
            text = "…",
            choices = {
                { label = "Hold out your hand.",
                  warn = "[WIS]",                        -- UI hint: [Attr] | risk | safe
                  check = { attr = "WIS", dc = 11 },     -- optional
                  success = { deltas = {…}, text = "…", next = "E02B", delayYears = 5 },
                  failure = { deltas = {…}, text = "…" } },
                { label = "Stand still.",
                  deltas = { attr = { WIS = 1 } }, text = "…" },   -- flat effect
            },
        }

    Deltas = {
        health, healthMaxAdjust, exp, coin, karma, notoriety,
        attr = { WIS = 1 }, flags = { "has_dog" }, clearFlags = { "family_poor" },
    }

    Rules the content obeys (design brief §4.1): two or three choices, never
    four; no choice obviously correct; common choices boring on purpose;
    never a number in the prose; never a wink.

    Two tiers, and the difference matters:

    * Events.All — the authored beats of a life. They fire once a
      run and are never recycled, because a beat that repeats stops being one.
    * Events.Repeatable — ordinary life: work, weather, illness, a debt, a
      neighbour. Each carries `cooldown`, the number of years before it may
      come round again. Small deltas, wide age bands.

    The draw spends an authored event if one is eligible, otherwise rolls the
    age band's repeat chance (Config.EventDraw) for a generic, otherwise serves
    a quiet year from Config.QuietYearLines. A year is never blank.
]]

local Config = require(script.Parent.Config)
local Rng = require(script.Parent.Rng)

local Events = {}

-- Stage bands. The brief splits the playable life into childhood,
-- adolescence and adulthood (old age shares the adulthood pool).
function Events.stageFor(age)
    if age <= 12 then
        return "childhood"
    elseif age <= 17 then
        return "adolescence"
    end
    return "adulthood"
end

-- ===========================================================================
-- The event table. Prose reused (nearly verbatim) from design-brief-v0.md
-- §4.5, with the brief's older attribute names mapped onto the eight:
-- Will -> WIS, Agility -> DEX, Intellect -> INT, Presence -> CHA.
-- ===========================================================================

Events.All = {
    ------------------------------------------------------------------ childhood
    {
        id = "E02_DOG",
        title = "The Dog",
        stage = "childhood",
        ageMin = 4,
        ageMax = 6,
        weight = 12,
        text = "There is a dog in the yard. It is not your family's dog. It is thin in the way that "
            .. "means it has been thin for a long time, and it has stopped walking toward the gate. "
            .. "It is looking at you without much interest. Your mother is inside, and the door is not shut.",
        choices = {
            {
                label = "Hold out your hand.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 11 },
                success = {
                    text = "You get a hand on its ribs before it decides you are not food. It stays. "
                        .. "Your mother comes out, sees it, and says nothing, which from her is permission.",
                    deltas = { attr = { WIS = 1 }, flags = { "has_dog" }, karma = 1 },
                    next = "E02B_DOG_AGAIN",
                    delayYears = 5,
                },
                failure = {
                    text = "It is faster than something that thin should be. Your mother hears you from "
                        .. "inside and is out the door before the second scream. She cleans it and does not "
                        .. "scold you, and you understand that she is frightened, which frightens you more.",
                    deltas = { health = -8, healthMaxAdjust = -2, attr = { WIS = 2 } },
                },
            },
            {
                label = "Stand still.",
                warn = "safe",
                text = "It looks at you for a while. Then it goes. You remember this longer than it "
                    .. "deserves, and you will still be able to picture it at sixty.",
                deltas = { attr = { WIS = 1 } },
            },
            {
                label = "Run for the door.",
                warn = "safe",
                text = "You are inside before it decides anything. Your mother does not look up from the "
                    .. "pot. Nothing happens, and you learn, at four, that nothing happening is a thing a "
                    .. "person can arrange.",
                deltas = { attr = { DEX = 1 } },
            },
        },
    },

    {
        id = "E02B_DOG_AGAIN",
        title = "The Dog, Again",
        stage = "childhood",
        ageMin = 8,
        ageMax = 14,
        weight = 12,
        chainOnly = true,
        text = "The dog is old now and it has decided that the end of your bed is its bed. It has also "
            .. "decided that a man coming up the lane at dusk is worth standing up for. You hear it before "
            .. "you hear the man. By the time you are at the door, the man has stopped, and is holding his "
            .. "hands where you can see them, and is saying your father's name.",
        choices = {
            {
                label = "Call the dog off.",
                warn = "safe",
                text = "The man has come a long way to say a short thing. The dog lies back down and watches "
                    .. "him the whole time he is in the house. Afterwards nobody explains anything to you, "
                    .. "which is how you know it was meant for you.",
                deltas = { attr = { CHA = 1 }, karma = 1, flags = { "heard_the_news" } },
            },
            {
                label = "Let it stand.",
                warn = "risk",
                text = "The dog does what it is for. The man does not run, which is either brave or "
                    .. "professional, and you will spend years working out which. He leaves without saying "
                    .. "the short thing, and the news arrives late, and worse.",
                deltas = { notoriety = 2, attr = { WIS = 1 } },
            },
        },
    },

    {
        id = "E_COIN_IN_ROAD",
        title = "What Was in the Road",
        stage = "childhood",
        ageMin = 6,
        ageMax = 10,
        weight = 10,
        text = "There is a coin in the road, half under the mud, and it is silver. Nothing in your house "
            .. "is silver. You look up and down the lane twice, the way you have seen adults check the "
            .. "weather, and the lane is empty and has been for a while.",
        choices = {
            {
                label = "Put it in your shoe and say nothing.",
                warn = "risk",
                text = "You keep it. You do not spend it, which is worse, because a coin you cannot spend "
                    .. "is a coin you have to think about. You will still know where it is in twenty years.",
                deltas = { coin = 15, karma = -2, flags = { "kept_the_coin" }, attr = { LUK = 1 } },
                next = "E_COIN_COMES_BACK",
                delayYears = 20,
            },
            {
                label = "Leave it where it is.",
                warn = "safe",
                text = "You step over it and go home and tell your mother about it, and she says that was "
                    .. "right, and something in the way she says it tells you that someone will come back "
                    .. "for it.",
                deltas = { karma = 1, attr = { WIS = 1 } },
            },
            {
                label = "Take it to the shrine.",
                warn = "safe",
                text = "The priest takes it with both hands and puts it in a box that is already nearly "
                    .. "empty, and thanks you by name, which no adult outside your family has done before.",
                deltas = { karma = 3, attr = { PIE = 1 } },
            },
        },
    },

    {
        id = "E03_LEDGER",
        title = "The Ledger",
        stage = "childhood",
        ageMin = 8,
        ageMax = 11,
        weight = 12,
        requires = { flags = { "family_poor" } },
        text = "Your father owes money to a man in the next village, and the man has started coming on "
            .. "the days when the road is dry. Your father is not a bad man and this is the problem: he is "
            .. "bad at this, and good at other things, and the family eats because of the other things.\n\n"
            .. "This morning there is a slate by the door with numbers on it. Your father cannot read. You can.",
        choices = {
            {
                label = "Read it to him. All of it.",
                warn = "[INT]",
                check = { attr = "INT", dc = 10 },
                success = {
                    text = "You read it twice to be sure and he listens with his hands still. Then he goes "
                        .. "out to the yard and stands there for a while. In the evening he asks you to teach "
                        .. "him the numbers. He is a poor student and he is not ashamed, and neither of you "
                        .. "ever mentions this day again.",
                    deltas = { attr = { INT = 2 }, karma = 2, flags = { "father_literate_late" } },
                },
                failure = {
                    text = "You read it and he listens and then he takes the slate away from you and does "
                        .. "the sum again himself, out loud, wrong, twice. He knows it is wrong. You both "
                        .. "know, and there is nothing either of you can do with that.",
                    deltas = { attr = { INT = 1, WIS = 1 }, karma = 1 },
                },
            },
            {
                label = "Read it, and leave out the last line.",
                warn = "risk",
                text = "It is not a lie. It is a kindness with a lie inside it. He sleeps. You do not, and "
                    .. "you find that you are quite good at this, and that you are going to have to decide "
                    .. "what kind of person that makes you.",
                deltas = { attr = { INT = 1, CHA = 2 }, karma = -4, flags = { "learned_to_trim" } },
            },
            {
                label = "Say you cannot read it either.",
                warn = "risk",
                text = "He nods and puts the slate away. You are eight and you have just learned that being "
                    .. "needed is a burden you can decline. He never asks again. Neither of you ever knows "
                    .. "whether he believed you.",
                deltas = { attr = { CHA = 1 }, karma = -1, flags = { "declined_to_help" } },
            },
        },
    },

    {
        id = "E_WINTER_FEVER",
        title = "The Fever",
        stage = "childhood",
        ageMin = 3,
        ageMax = 11,
        weight = 8,
        text = "The fever comes in the wet month, when the whole village is coughing and nobody has the "
            .. "strength to be frightened about it. You spend four days on the floor by the fire on a "
            .. "blanket that used to be something else. On the third day the room is very bright and "
            .. "everyone in it is talking about you and none of them are talking to you.",
        choices = {
            {
                label = "Sleep. Let it run.",
                warn = "risk",
                text = "You wake up on the fifth day, thin, and hungry, and your mother is holding the "
                    .. "blanket in both fists and pretending to be busy. You never find out how close it was, "
                    .. "because nobody in this house says that kind of thing.",
                deltas = { health = -12, attr = { VIT = 1 }, karma = 0 },
            },
            {
                label = "Get up and fetch the water anyway.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 12 },
                success = {
                    text = "You get up, because somebody has to, and the cold makes it easier to breathe. "
                        .. "You are not stronger afterwards. You are simply a person who got up, and that "
                        .. "stays with you longer than the fever.",
                    deltas = { health = -8, attr = { VIT = 1, WIS = 1 } },
                },
                failure = {
                    text = "You make it as far as the door and sit down in it. Your father carries you back "
                        .. "without saying anything, which costs him, because he is also ill and does not "
                        .. "admit it for another twenty years.",
                    deltas = { health = -20, healthMaxAdjust = -1, attr = { WIS = 1 } },
                },
            },
            {
                label = "Ask the priest to come and stand over you.",
                warn = "safe",
                text = "He comes on the second day and says the words, and puts a hand on your head that is "
                    .. "warmer than it should be, and later you will not be able to tell anyone whether it was "
                    .. "that or the sleep. He remembers you. That is the part that matters, and you will not "
                    .. "find out why for a long time.",
                deltas = { health = -4, karma = 2, attr = { PIE = 1 }, flags = { "known_to_the_shrine" } },
            },
        },
    },

    --------------------------------------------------------------- adolescence
    {
        id = "E_COIN_COMES_BACK",
        title = "The Coin Comes Back",
        stage = "adulthood",
        ageMin = 20,
        ageMax = 45,
        weight = 10,
        chainOnly = true,
        requires = { flags = { "kept_the_coin" } },
        text = "The man at the market takes your coin, looks at it, and puts it back in your hand "
            .. "without taking anything for it. He says the year it was struck, and then he says a name, "
            .. "and it is not your name, and he does not raise his voice at any point in the conversation.",
        choices = {
            {
                label = "Give him back the coin, and what it is worth.",
                warn = "safe",
                text = "He takes it without thanks, which is somehow more frightening than anger. You have "
                    .. "bought back a coin you stole when you were eight, at a price you will not be able to "
                    .. "explain to anyone.",
                deltas = { coin = -35, karma = 3, clearFlags = { "kept_the_coin" }, attr = { WIS = 1 } },
            },
            {
                label = "Deny ever seeing it.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 13 },
                success = {
                    text = "You look him in the eye and it works, which is the worrying part. He shrugs and "
                        .. "goes back to the stall. You walk home by a longer road than you needed to.",
                    deltas = { attr = { CHA = 1 }, karma = -1, notoriety = 2 },
                },
                failure = {
                    text = "You are already talking when you realise he has stopped listening. He does not "
                        .. "accuse you of anything. He simply writes something down and turns the page, and "
                        .. "the page is not the same book you have seen other people write in.",
                    deltas = { notoriety = 8, karma = -2, attr = { CHA = 1 } },
                },
            },
        },
    },

    {
        id = "E04_RECRUITER",
        title = "The Recruiter",
        stage = "adolescence",
        ageMin = 16,
        ageMax = 18,
        weight = 18,
        text = "The man from the guild has a table outside the shrine and a copper plate on it, and he "
            .. "has been here for two days, and he is bored enough to be honest. He says: adventurers die. "
            .. "He says it the way a man says the road is muddy. He says the guild pays for the funeral if "
            .. "you make Silver, and does not if you don't.\n\nBehind him, a woman with a spear is "
            .. "pretending not to listen. She is missing the top of one ear.",
        choices = {
            {
                label = "Take the plate.",
                warn = "safe",
                text = "He writes your name down and gets two letters of it wrong and does not ask. The "
                    .. "plate is copper, it is thin, and it is the first thing you have ever owned that was "
                    .. "issued to you rather than given.",
                deltas = {
                    coin = 30,
                    exp = 120,
                    notoriety = 1,
                    flags = { "adventurer" },
                },
            },
            {
                label = "Ask what happened to her ear.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "He stops being bored for a moment. 'Ask her,' he says. You ask her. She tells "
                        .. "you, in four sentences, and one of them is about a thing with too many arms, and "
                        .. "you decide on the spot that you would rather be that than a farmer, and you will "
                        .. "spend thirty years finding out that this was not a decision so much as a symptom.",
                    deltas = { attr = { CHA = 1 }, exp = 140, flags = { "adventurer", "spear_mentor" } },
                },
                failure = {
                    text = "She looks at you the way a bricklayer looks at a wall that has been built by "
                        .. "somebody else, and then she tells you: 'Ask the man who is paying you.' The man "
                        .. "who is paying you is now looking at the shrine, and the conversation is over.",
                    deltas = { attr = { WIS = 1 }, exp = 60, flags = { "adventurer" } },
                },
            },
            {
                label = "Walk away.",
                warn = "safe",
                text = "You go home. The guild comes back in four years and by then you have a trade and a "
                    .. "wife and the man behind the table is a different man and the copper plate is a "
                    .. "different plate. You will think about this at forty, briefly, while doing something "
                    .. "else.",
                deltas = { karma = 1, coin = 10, flags = { "stayed_home" } },
            },
        },
    },

    ----------------------------------------------------------------- adulthood
    {
        id = "E05_COPPER_PLATE",
        title = "The Board",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 26,
        weight = 16,
        requires = { flags = { "adventurer" } },
        text = "The guild hall smells of wet wool and old blood and it is louder than you expected. "
            .. "There is a board with work on it. There is a man whose job is to tell you which of the "
            .. "work will kill you, and he does this badly, because he has been doing it for twenty years "
            .. "and has stopped looking at the board.\n\nOn the far wall, behind glass, is a sheet of "
            .. "paper with one number written on it. Underneath, in a different hand: do not.",
        choices = {
            {
                label = "Ask what the number is.",
                warn = "safe",
                text = "The man behind the counter does not look up. 'A knight,' he says. 'Not a man on a "
                    .. "horse. The other kind.' You ask where. He says the plains, and then he says the "
                    .. "plains are fine, and then he stops talking to you and starts talking to the person "
                    .. "behind you.",
                deltas = { attr = { INT = 1 }, notoriety = 2, flags = { "knows_the_number" } },
            },
            {
                label = "Take the job nobody else would take.",
                warn = "[risk]",
                check = { attr = "DEX", dc = 14 },
                success = {
                    text = "You come back with the thing's head and a limp you will keep. The man behind "
                        .. "the counter writes your name on the board in a better hand than he wrote it "
                        .. "last time.",
                    deltas = {
                        exp = 420,
                        coin = 240,
                        notoriety = 8,
                        healthMaxAdjust = -5,
                        health = -15,
                        flags = { "took_the_bad_job" },
                    },
                },
                failure = {
                    text = "You come back. Two of the four of you come back. The man behind the counter "
                        .. "does not say anything about the other two, because there is a form for that, "
                        .. "and he is filling it in before you have left the room.",
                    deltas = {
                        exp = 150,
                        coin = 60,
                        karma = -2,
                        notoriety = 4,
                        healthMaxAdjust = -15,
                        health = -30,
                        flags = { "lost_a_party" },
                    },
                },
            },
            {
                label = "Take the safe work.",
                warn = "safe",
                text = "You spend the season clearing vermin out of granaries. It is honest, it is dull, "
                    .. "and it pays. In nine years you will be the only one of your intake still alive, and "
                    .. "you will not be sure whether that is a victory.",
                deltas = { exp = 80, coin = 90, flags = { "still_alive" } },
            },
        },
    },

    {
        id = "E06_CART_LEFT_BEHIND",
        title = "What the Cart Left Behind",
        stage = "adulthood",
        ageMin = 22,
        ageMax = 45,
        weight = 12,
        text = "Two days after the fighting the plain is still not quiet, and it is not the dying that "
            .. "makes the noise. You have come for the metal. Swords do not care who won.\n\nWhat is wrong "
            .. "is the shape of the dead. A man does not fall in a straight line. Nine of them have.",
        choices = {
            {
                label = "Take the metal and go.",
                warn = "safe",
                text = "Good steel, most of it, and a horse that will need a new owner. You are three miles "
                    .. "away before you let yourself think about the line, and then you think about it for "
                    .. "the rest of your life, at odd moments, in good weather.",
                deltas = { coin = 180, notoriety = 3, karma = -3, flags = { "saw_the_line" } },
            },
            {
                label = "Look at the line properly.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 12 },
                success = {
                    text = "You go down it, one to nine. They are facing the same way. None of them are "
                        .. "burnt and none of them are cut. At the end there is a boy with a spear who is not "
                        .. "more than fifteen and who is, you are almost certain, still warm. You do not take "
                        .. "his spear.",
                    deltas = { attr = { WIS = 3, INT = 1 }, karma = 4, flags = { "knows_the_line" } },
                },
                failure = {
                    text = "You get four steps in and then you are on your knees in the mud being sick, and "
                        .. "the noise in the plain is your own blood in your ears. You leave the metal. You "
                        .. "leave all of it. It takes you two days to walk home and you do not remember "
                        .. "either of them.",
                    deltas = { attr = { WIS = -1 }, health = -10, flags = { "broke_at_the_line" } },
                },
            },
            {
                label = "Mark the place and tell someone.",
                warn = "safe",
                text = "You spend the day piling stones, which is work for a man with no plan. A priest from "
                    .. "a village you have never heard of arrives on the third day, and does the rest, and "
                    .. "asks you for your name, and writes it down. Nothing comes of it for eleven years.",
                deltas = { karma = 8, coin = -20, attr = { PIE = 1 }, flags = { "marked_the_place" } },
                next = "E_TEMPLE_FAVOUR",
                delayYears = 11,
            },
        },
    },

    {
        id = "E_TEMPLE_FAVOUR",
        title = "Eleven Years",
        stage = "adulthood",
        ageMin = 28,
        ageMax = 70,
        weight = 12,
        chainOnly = true,
        requires = { flags = { "marked_the_place" } },
        text = "The priest is old now and the shrine he keeps is not the one you expected. He has a "
            .. "document with your name in it, written in his own hand eleven years ago, and he has "
            .. "carried it in a case ever since, and he has been waiting for a year when it would be "
            .. "useful to you rather than to him.\n\nHe says the shrine remembers the stones. He does not "
            .. "say who told it to.",
        choices = {
            {
                label = "Let him do what he came to do.",
                warn = "safe",
                text = "He says the words and puts a hand on your head that is warmer than it should be, "
                    .. "and you sleep for a day and a night afterwards. When you wake, the ache you had "
                    .. "forgotten you had is gone, and he is already at the door.",
                deltas = { health = 25, karma = 4, attr = { PIE = 2 }, flags = { "temple_favour_used" } },
            },
            {
                label = "Ask him what a favour is worth in coin.",
                warn = "risk",
                text = "He does not look disappointed, which is worse. He names a figure that is more than "
                    .. "the shrine has, and then he finds it, and then he gives it to you, and he does not "
                    .. "ask you for anything, which you will think about at odd moments for years.",
                deltas = { coin = 120, karma = -3, attr = { PIE = -1 } },
            },
        },
    },

    {
        id = "E07_RIDER",
        title = "The Rider",
        stage = "adulthood",
        ageMin = 20,
        ageMax = 55,
        weight = 6,
        deathText = "the rider on the road, which did not slow down and did not see them",
        text = "A rider is coming down the road and it is not in a hurry.\n\nIt is taller than a mounted "
            .. "man ought to be. The horse beneath it is not a horse. There is a cart ahead of you on the "
            .. "road, stopped, and the cart's people are on the seat looking at it the way people look at "
            .. "weather that is coming directly at them.\n\nThe rider does not slow. It passes the cart at "
            .. "a walk. The cart's horse screams and the people on the seat do not, and then it is past "
            .. "them, and the road is quiet, and it is coming toward you. It has not turned its head.",
        choices = {
            {
                label = "Step off the road, kneel, and look at the ground.",
                warn = "safe",
                text = "The cold comes and goes. It takes a while. When you look up the road is empty and "
                    .. "the cart is where it was, and the people on it are where they were, and none of them "
                    .. "are moving, and none of them have been cut or burnt or touched. You do not tell "
                    .. "anyone what you saw. Mostly because of the part you are sure of and cannot say out "
                    .. "loud: that it did not see you either.",
                deltas = { attr = { WIS = 2 }, flags = { "knows_what_passes" } },
            },
            {
                label = "Run.",
                warn = "[DEX]",
                check = { attr = "DEX", dc = 14 },
                success = {
                    text = "You are over the wall and in the field and you keep going until the field ends. "
                        .. "The thing on the road does not change pace for you. You are alive, and you are "
                        .. "alive for a reason that has nothing to do with you, and that is a fact you will "
                        .. "carry longer than the run.",
                    deltas = { attr = { DEX = 2, WIS = -1 }, flags = { "ran_from_it" } },
                },
                failure = {
                    text = "You get ten steps. You do not feel the blow. You feel the ground, which is "
                        .. "cold, and you have time to be embarrassed before you have time to be afraid.",
                    deltas = { health = -999, flags = { "ran_from_it" } },
                },
            },
            {
                label = "Draw.",
                warn = "risk",
                text = "You are not a fool. You are something worse: a person who has decided. The thing "
                    .. "on the road does not stop walking, does not turn its head, and does not appear to "
                    .. "notice that you have moved. Your hands are steady. It is the only part of this you "
                    .. "will be proud of, and no one will ever know about it.\n\nIt does not slow down.",
                deltas = { health = -999, flags = { "stood_in_the_road" } },
            },
        },
    },

    {
        id = "E09_OFFICE",
        title = "The Office With No Queue",
        stage = "adulthood",
        ageMin = 25,
        ageMax = 52,
        weight = 10,
        text = "The office has three clerks and no queue, and it is the fastest thing in the city. A "
            .. "woman with grey skin and no expression takes your name, your trade, and your village, "
            .. "writes them in a book, and tells you the tax is lower this year than it was last year.\n\n"
            .. "It is. That is the part nobody in the street can explain.\n\nThe undead do not want your "
            .. "soul. They want the ledger balanced. They are extremely good at it.",
        choices = {
            {
                label = "Sign.",
                warn = "safe",
                text = "You sign. The tax is lower. The road is repaired. The bandits are gone, and so are "
                    .. "two families who used to live on the road, and no one knows where they went, and the "
                    .. "road is very good now.",
                deltas = { coin = 60, karma = -3, notoriety = -1, flags = { "signed_the_roll" } },
            },
            {
                label = "Ask where the two families went.",
                warn = "risk",
                text = "The clerk looks up. She is not offended and she is not amused. She turns the book "
                    .. "around, finds the page, and shows you the entry. It is very neatly written. It says "
                    .. "what happened and who ordered it and the date, and there is a column for the reason, "
                    .. "and the reason is four words long, and it is a good reason.",
                deltas = { attr = { INT = 2, WIS = -1 }, karma = 2, flags = { "read_the_page" } },
                next = "E_CONSCIENCE",
                delayYears = 6,
            },
            {
                label = "Refuse to sign.",
                warn = "risk",
                text = "You do not sign. Nothing happens. Nothing continues to happen for eleven years, "
                    .. "and then a different clerk, with a different book, comes to your door with a form "
                    .. "about the road.",
                deltas = { notoriety = 3, coin = -15, karma = 1, flags = { "refused_the_roll" } },
            },
        },
    },

    {
        id = "E_CONSCIENCE",
        title = "A Column For the Reason",
        stage = "adulthood",
        ageMin = 28,
        ageMax = 70,
        weight = 12,
        chainOnly = true,
        requires = { flags = { "read_the_page" } },
        text = "You have had six years to stop thinking about the column, and the column has had six "
            .. "years to get better. It has. You can still read the four words from memory, and you have "
            .. "started to notice that you agree with three of them, and that the fourth one is the one "
            .. "you would have written.",
        choices = {
            {
                label = "Write it down and give it to someone who will use it.",
                warn = "risk",
                text = "You copy the entry out by hand, badly, and leave it where a person who collects "
                    .. "such things will find it. Nothing happens to you. Something happens to the clerk, "
                    .. "which you did not intend and cannot undo.",
                deltas = { karma = 5, notoriety = 8, attr = { CHA = 1 } },
            },
            {
                label = "Keep it. Say nothing. Take the cheaper tax.",
                warn = "safe",
                text = "You keep it, which is a decision you make once and then make again every year "
                    .. "without noticing. The road stays good. You are, on paper, a well-run man in a "
                    .. "well-run district.",
                deltas = { karma = -5, coin = 40, notoriety = -1 },
            },
        },
    },

    {
        id = "E10_GRAIN_RIOT",
        title = "The Grain Riot",
        stage = "adulthood",
        ageMin = 24,
        ageMax = 48,
        weight = 10,
        text = "The price of grain has doubled in a month. Everyone knows why and no one agrees. There "
            .. "is a crowd outside the granary and it is no longer the kind of crowd that is waiting for "
            .. "an announcement.\n\nYou are standing in it. You did not decide to be here. You were "
            .. "walking home.",
        choices = {
            {
                label = "Leave.",
                warn = "safe",
                text = "You turn around and go the long way and hear about it from your neighbour, who was "
                    .. "also there, and who is now a person who was there. Eight people die. You are not one "
                    .. "of them and it was not a decision, exactly, which is the part that sits badly.",
                deltas = { flags = { "left_the_crowd" } },
            },
            {
                label = "Get the children out.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 12 },
                success = {
                    text = "You are not a leader and you do not try to be. You put your hands on shoulders "
                        .. "and you say the same four words and you do not raise your voice, and by the time "
                        .. "the guard comes there are eleven of you going down the side street and none of "
                        .. "you are running.",
                    deltas = { karma = 10, attr = { CHA = 2 }, notoriety = 2 },
                },
                failure = {
                    text = "You get three of them. The fourth will not let go of the gate. You have to "
                        .. "choose, and you choose, and the choosing takes half a second, and you will be "
                        .. "able to account for that half second to yourself for the rest of your life and "
                        .. "it will never be enough.",
                    deltas = { karma = 5, attr = { WIS = 1 }, health = -15, flags = { "the_gate" } },
                },
            },
            {
                label = "Throw a stone.",
                warn = "risk",
                text = "The stone is not the reason the granary burns. The stone is the reason the guard "
                    .. "charges. You are quite fast and you get away and for about a year you tell the story "
                    .. "as though it were funny.",
                deltas = { notoriety = 12, attr = { DEX = 1 }, karma = -6, flags = { "wanted_in_that_city" } },
            },
        },
    },

    {
        id = "E12_STAIRS",
        title = "Stairs",
        stage = "adulthood",
        ageMin = 62,
        ageMax = 110,
        weight = 15,
        text = "You have started counting stairs before you climb them.\n\nIt is not fear. It is "
            .. "arithmetic, and the arithmetic is not going your way. There are twelve stairs to your own "
            .. "door and you have been doing them for thirty years and this year, for no reason that has "
            .. "anything to do with a decision, they are twelve.",
        choices = {
            {
                label = "Move the bed downstairs.",
                warn = "safe",
                text = "You move the bed down. Your daughter offers to come and does not, which is the "
                    .. "correct outcome and you both know it. For a while you are embarrassed. Then you are "
                    .. "not, and the not-being-embarrassed is worse.",
                deltas = { health = -2, healthMaxAdjust = -4, karma = 0 },
            },
            {
                label = "Keep climbing them.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 11 },
                success = {
                    text = "You climb them every day. By spring it is eleven stairs again, in the way that "
                        .. "these things are. You do not tell anyone about this, because there is no one "
                        .. "left who would understand why it mattered.",
                    deltas = { health = -1, attr = { VIT = 1, WIS = 2 }, flags = { "kept_climbing" } },
                },
                failure = {
                    text = "You fall on the sixth. You lie there for a while doing an inventory, and the "
                        .. "inventory is worse than the fall. Someone finds you in the afternoon. Nothing is "
                        .. "broken. You will tell them it was three stairs.",
                    deltas = { health = -20, healthMaxAdjust = -10, flags = { "the_fall" } },
                },
            },
            {
                label = "Give the house to your child and move in with them.",
                warn = "safe",
                text = "You give away the house. It is a sensible thing to do and you do it in an "
                    .. "afternoon. Your grandchild asks you a question about the old king and you find that "
                    .. "you can answer it, and that you are the only person in the room who can, and nobody "
                    .. "writes it down.",
                deltas = { coin = -150, karma = 3, health = 5, flags = { "the_house_given" } },
            },
        },
    },

    ------------------------------------------------------------- into a fight
    -- The card that leads into turn-based combat (§5.1). The fight is the
    -- RESOLUTION of this year's decision, so combat does not spend a year. The
    -- `combat` block is shown on the card before the player commits: what is
    -- down there, what losing costs, and the health they would be taking in.
    {
        id = "E_GRANARY_CELLAR",
        title = "The Count",
        stage = "adulthood",
        ageMin = 17,
        ageMax = 34,
        weight = 20,
        text = "The keeper of the granary has counted the sacks eleven times, and the number is the "
            .. "same every time, and it is wrong. He does not say rats. He says the floor.\n\nWhere the "
            .. "floor meets the wall there is a hole, and the grain around it has been eaten clean in a "
            .. "cone, the way something serious eats and not the way vermin do. He offers you the guild's "
            .. "rate less a little for the inconvenience of being asked, which is how you know he has "
            .. "already asked somebody else. The hatch is up on its ring while he is still talking. He is "
            .. "standing well back from it.",
        combat = {
            encounter = "ENC_GRANARY_JOB",
            severity = "defeat",
            warning = "The hole is wider than the keeper's fist, and the floorboards about it are soft. "
                .. "Whatever is under the grain has been eating well for a month.",
            stakes = "Nothing down there has any use for you dead. If it goes badly you will wake up on "
                .. "the floor with a lighter purse and ribs that will not be quiet for a while.",
            onWin = {
                text = "You come up the ladder with a tail in your fist and a smell in your clothes that "
                    .. "will take a season to leave. The keeper counts the sacks again with you standing "
                    .. "there, and this time the number is right, and he pays you in the yard where the "
                    .. "neighbours can see it happen, which is worth more to him than the coin.",
                deltas = { notoriety = 3 },
            },
            onLose = {
                text = "You do not remember the ladder. You remember the granary floor and the keeper's "
                    .. "boots and his voice going over you to somebody else, about what the guild owes for "
                    .. "this and who is going to carry you. Your purse is lighter than it should be and he "
                    .. "does not look at you when you leave.",
                severity = "defeat",
            },
            onFlee = {
                text = "You come out of the hatch without the lamp and without the coin, and the keeper "
                    .. "does not argue. The way he does not argue is the whole of it. By the time it is "
                    .. "told in the yard it is no longer a story about rats.",
            },
        },
        choices = {
            {
                label = "Go down and clear it.",
                warn = "[risk]",
                startsCombat = true,
                text = "You take the lamp down first. The hatchet is no use in the dark.",
            },
            {
                label = "Tell him it is the mason's work, not yours.",
                warn = "safe",
                text = "You tell him what any mason would tell him, which is the truth, and it is not the "
                    .. "answer he paid a morning of his own time to get. He gives you something for the "
                    .. "walk. The hole is still there when you go past the granary the following year, and "
                    .. "there is a board over it, and the board is doing nothing.",
                deltas = { coin = 6, attr = { WIS = 1 } },
            },
            {
                label = "Smoke them out from above.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "You bank the straw at the hatch and keep the fire small and feed it until the "
                        .. "cellar gives up its air. Nothing comes out the hole. What comes out is a smell "
                        .. "you will recognise for the rest of your life, and eleven sacks that are still "
                        .. "worth money, and a keeper who tells the story better than you do.",
                    deltas = { coin = 45, exp = 45, attr = { INT = 1 }, flags = { "smoked_the_cellar" } },
                },
                failure = {
                    text = "The straw takes faster than you meant it to and gets into the joists, and for a "
                        .. "quarter of an hour the granary is the most interesting thing in the street. The "
                        .. "fire is put out. The grain nearest the hatch is not grain any more. He does not "
                        .. "shout, which is worse, and you pay for the sacks out of what you have.",
                    deltas = { coin = -25, karma = -1, attr = { WIS = 1 } },
                },
            },
        },
    },
}

-- ===========================================================================
-- Eligibility and draw
-- ===========================================================================

--- Look up a stat by key: an attribute, or one of the tracked resources.
-- ===========================================================================
-- The repeatable tier. Ordinary life, not the beats of a life.
--
-- These are the years between the authored events: work, weather, illness, a
-- debt, a neighbour, a decision about money or family. Everything here is
-- `repeatable = true` with a `cooldown` in years, so the same one can come
-- round again in a long life without reading as recycled. Deltas are
-- deliberately small — a generic that pays +2 STR is a farm, not a year.
--
-- Authored content stays in Events.All above and is never recycled.
-- ===========================================================================

Events.Repeatable = {
    ------------------------------------------------------------------ childhood
    {
        id = "R_CHILD_FEVER",
        title = "The Fever",
        stage = "childhood",
        ageMin = 3,
        ageMax = 11,
        weight = 10,
        repeatable = true,
        cooldown = 5,
        text = "You wake because your teeth are loud. The room is a different size than it was, and "
            .. "someone has left the lamp burning, which nobody does.\n\nThere is a weight on your chest "
            .. "that is not a weight, and when you try to say so, the sound that comes out is not a word. "
            .. "Downstairs, your mother is moving about, and the boards say she is not going to bed.",
        choices = {
            {
                label = "Lie still and say nothing.",
                warn = "risk",
                text = "You are still there in the morning, which surprises you slightly. Nobody ever "
                    .. "knows you were ill, and you keep it that way, the way you will keep a great many "
                    .. "things that were none of anybody's business.",
                deltas = { health = -6, attr = { VIT = 1 } },
            },
            {
                label = "Call for her.",
                warn = "safe",
                text = "She is up the stairs before the second word. She sits with you until the lamp "
                    .. "burns down and does not once tell you it is nothing. It is not nothing. She is "
                    .. "frightened, and she is good at it.",
                deltas = { health = -3, attr = { WIS = 1 } },
            },
            {
                label = "Get up and go down to her.",
                warn = "risk",
                text = "You make it to the third step before your legs stop being yours. She carries you "
                    .. "back up, which she should not be able to do, and says nothing about it, then or "
                    .. "ever.",
                deltas = { health = -8, attr = { VIT = 1, WIS = 1 } },
            },
        },
    },

    {
        id = "R_CHILD_WATER",
        title = "The Water",
        stage = "childhood",
        ageMin = 5,
        ageMax = 12,
        weight = 12,
        repeatable = true,
        cooldown = 3,
        text = "The well is at the end of the lane and the bucket comes up heavy, and you have been given "
            .. "the job because you are big enough to have it and not big enough to refuse it.\n\n"
            .. "On the way back the bucket finds the edge of a stone and half of it goes into the dust. "
            .. "There is nobody on the lane. There is time to go back.",
        choices = {
            {
                label = "Go back and fill it again.",
                warn = "safe",
                text = "You go back. Your arms do not thank you and the afternoon is gone, but the pot "
                    .. "is full, and you have learned what the whole job costs instead of what half of it "
                    .. "costs.",
                deltas = { attr = { STR = 1 }, exp = 5 },
            },
            {
                label = "Take the half bucket home.",
                warn = "risk",
                text = "Nobody says anything, which is worse than being told. At the table there is less "
                    .. "of it than there should be, and you eat it anyway, and you are the only one at that "
                    .. "table who knows why.",
                deltas = { attr = { WIS = 1, VIT = -1 } },
            },
            {
                label = "Ask the neighbour's boy to help you carry it.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 10 },
                success = {
                    text = "He does it, and complains the whole way, and comes back the next day without "
                        .. "being asked. That is how you find out that most people will do a thing if "
                        .. "someone is standing there while they do it.",
                    deltas = { attr = { CHA = 1 }, exp = 5 },
                },
                failure = {
                    text = "He looks at the bucket, then at you, and goes inside. You carry it yourself, "
                        .. "and the walk back is longer than it was, and you are angry in a way you cannot "
                        .. "put anywhere useful.",
                    deltas = { attr = { STR = 1, CHA = -1 } },
                },
            },
        },
    },

    {
        id = "R_CHILD_NEIGHBOUR",
        title = "What the Boy Broke",
        stage = "childhood",
        ageMin = 6,
        ageMax = 12,
        weight = 10,
        repeatable = true,
        cooldown = 5,
        text = "The pot by the door is in three pieces, and the neighbour's boy is standing over it, and "
            .. "he is not running, which means he has decided something already.\n\nHe says it was the "
            .. "dog. There is no dog. He says this without any hope at all, the way people say things "
            .. "they have already stopped believing, and you understand that he is not asking you to "
            .. "believe him. He is asking you to agree.",
        choices = {
            {
                label = "Say it was the dog.",
                warn = "risk",
                text = "It costs you a beating and buys him one afternoon. He never thanks you. Years "
                    .. "later he will be the one who tells you what happened to your father's land, and "
                    .. "neither of you will mention the pot.",
                deltas = { karma = 2, attr = { CHA = 1 }, health = -2 },
            },
            {
                label = "Say what you saw.",
                warn = "safe",
                text = "He takes it, badly and loudly, and the two houses do not speak for a season over "
                    .. "it. You are told you did right, in the tone people use when they mean that you "
                    .. "made something harder for them.",
                deltas = { karma = 1, attr = { WIS = 1 } },
            },
            {
                label = "Say nothing at all.",
                warn = "risk",
                text = "You stand there with your mouth shut until an adult comes out and decides the "
                    .. "whole thing without you. That is the first time you notice how often that works.",
                deltas = { attr = { WIS = 1 }, karma = -1 },
            },
        },
    },

    --------------------------------------------------------------- adolescence
    {
        id = "R_WAGE_SHORT",
        title = "The Day's Wage",
        stage = "adolescence",
        ageMin = 13,
        ageMax = 17,
        weight = 12,
        repeatable = true,
        cooldown = 3,
        text = "You have been in the field for six days. At the end of it the farmer counts coin into "
            .. "your hand, slowly, the way a man counts when he wants you to watch him count, and it is "
            .. "short. Not by much. By enough that he knows you know.",
        choices = {
            {
                label = "Count it out loud, in front of him.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "He listens to the number, looks at your hands, and puts the rest in without "
                        .. "a word. Next week it is right the first time. He does not like you after "
                        .. "this, and he hires you again anyway.",
                    deltas = { coin = 12, attr = { CHA = 1 } },
                },
                failure = {
                    text = "He says you cannot count, then, when that does not land, that you were slow, "
                        .. "then that you should be grateful. You take the short wage and the afternoon "
                        .. "worth of it, and you remember his face better than you meant to.",
                    deltas = { coin = 6, attr = { WIS = 1 } },
                },
            },
            {
                label = "Take it and say nothing.",
                warn = "safe",
                text = "You take it. In the lane on the way home you work out the difference over a "
                    .. "month and what it would have bought, which is a thing you cannot undo by working "
                    .. "it out, and you do it anyway.",
                deltas = { coin = 6, attr = { WIS = 1 } },
            },
            {
                label = "Take it, and take a little back.",
                warn = "risk",
                text = "There is grain in the barn and no lock worth the name, and you are in and out "
                    .. "before the lamp is lit. It is a small amount. It is also the first thing you have "
                    .. "ever stolen, which is a fact that does not care about the amount.",
                deltas = { coin = 18, karma = -2, attr = { DEX = 1 } },
            },
        },
    },

    {
        id = "R_ENTRUSTED_COIN",
        title = "What the Money Was For",
        stage = "adolescence",
        ageMin = 13,
        ageMax = 17,
        weight = 10,
        repeatable = true,
        cooldown = 4,
        text = "You are sent to the market with coin for salt and a nail, and you are given the exact "
            .. "amount, and you are told the price of both, which means you are trusted, which is a new "
            .. "feeling and a heavy one.\n\nAt the third stall there is a thing you have wanted for two "
            .. "years. It costs less than the salt.",
        choices = {
            {
                label = "Buy the salt and the nail.",
                warn = "safe",
                text = "You come home with exactly what you were sent for and hand over the change, and "
                    .. "nothing at all is said about it, and it is the best afternoon you have had in a "
                    .. "while.",
                deltas = { coin = -2, karma = 1, attr = { WIS = 1 } },
            },
            {
                label = "Buy the thing, and say the price went up.",
                warn = "risk",
                text = "The lie is small and it holds, and it will hold for years, and it will be the "
                    .. "reason you are careful about your own face in front of people who know you. You "
                    .. "have the thing. You keep it where nobody looks.",
                deltas = { karma = -2, attr = { CHA = 1, LUK = 1 } },
            },
            {
                label = "Buy the thing and say nothing about it.",
                warn = "risk",
                text = "You come home short and cannot say why, and you stand there while the arithmetic "
                    .. "is done out loud twice. What is remembered is not the missing coin. It is that "
                    .. "you would not answer.",
                deltas = { coin = -5, karma = -1, attr = { WIS = 1 } },
            },
        },
    },

    {
        id = "R_ROOF_NEXT_DOOR",
        title = "The Roof Next Door",
        stage = "adolescence",
        ageMin = 13,
        ageMax = 17,
        weight = 10,
        repeatable = true,
        cooldown = 3,
        text = "The old man next door has a roof that will not survive the weather that is coming, and "
            .. "he has asked you, which costs him something to do. He can pay you in firewood, and the "
            .. "firewood is worth less than the day.\n\nYour own field wants you in it, and your father "
            .. "has not said which day, and will not.",
        choices = {
            {
                label = "Go up on the roof.",
                warn = "safe",
                text = "It takes the day and most of your hands. He watches from the ground and tells you "
                    .. "where to put things, badly, and when it is done he stands in his own doorway and "
                    .. "says thank you in a voice that has not done it much.",
                deltas = { karma = 2, attr = { STR = 1 }, exp = 10 },
            },
            {
                label = "Stay in your own field.",
                warn = "safe",
                text = "The weather comes, and the roof goes, and he moves in with his daughter across "
                    .. "the water and does not come back. Some decisions are only visible from the far "
                    .. "end of them.",
                deltas = { coin = 4, karma = -1, attr = { WIS = 1 } },
            },
            {
                label = "Do both, and do neither properly.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 11 },
                success = {
                    text = "You get the roof up and get the field in, and you are useless for a week "
                        .. "afterwards, and both men assume you chose them. Nobody finds out that you "
                        .. "did not.",
                    deltas = { karma = 1, attr = { STR = 1, VIT = 1 }, health = -4 },
                },
                failure = {
                    text = "You are on the roof in the rain at the end of it, and you have done it badly, "
                        .. "and the field is not in. The old man does not blame you. He is too old to "
                        .. "spend it on blame, which is somehow the part that stays.",
                    deltas = { health = -8, karma = 1, attr = { WIS = 1 } },
                },
            },
        },
    },

    ---------------------------------------------------------------- adulthood
    {
        id = "R_DEBT_NOTE",
        title = "The Note",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 55,
        weight = 12,
        repeatable = true,
        cooldown = 7,
        text = "There was a bad year, and in that year you signed something, and the man who holds it "
            .. "has been patient in a way that is worse than anger.\n\nHe is at the door on a dry day. "
            .. "He does not raise his voice. He says he is not here about the money, and then he talks "
            .. "about the money for a while, and you notice he has not sat down.",
        choices = {
            {
                label = "Pay what you have and agree the rest.",
                warn = "safe",
                text = "It is nearly everything in the house. He counts it, writes in his book, and shakes "
                    .. "your hand on the way out. You are poorer and you sleep, which you had stopped "
                    .. "doing, and which you had not admitted to anyone.",
                deltas = { coin = -30, karma = 1, attr = { WIS = 1 } },
            },
            {
                label = "Ask for another year.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 12 },
                success = {
                    text = "He looks at you for a long moment, then writes something and tears out the "
                        .. "page. It is not generosity. He has decided you are a better asset alive and "
                        .. "working, and you will spend some part of the coming year being glad about "
                        .. "that and some part of it not.",
                    deltas = { attr = { CHA = 1 }, notoriety = 1 },
                },
                failure = {
                    text = "He says no, pleasantly, and tells you what happens next in the same tone he "
                        .. "used about the weather. You find the money. You find it at a price you would "
                        .. "not have chosen.",
                    deltas = { coin = -40, karma = -1, attr = { WIS = 1 } },
                },
            },
            {
                label = "Take the long way home for a while.",
                warn = "risk",
                text = "You are careful for two seasons and it works, which means nobody comes, which "
                    .. "means nobody is coming. You keep the coin and something else goes: people on that "
                    .. "road know your face now, and know what it does when the subject comes up.",
                deltas = { coin = 10, notoriety = 2, karma = -1 },
            },
        },
    },

    {
        id = "R_GOING_ROUND",
        title = "Something Going Round",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 55,
        weight = 12,
        repeatable = true,
        cooldown = 5,
        text = "It starts in the next house and comes along the lane the way things come along lanes: "
            .. "the children first, then the old, and then whoever was holding one of them when it "
            .. "arrived.\n\nYou have work that will not wait, and there is a cough in your chest that "
            .. "was not there last week, and you are the only person in the house who can stand up at "
            .. "the moment.",
        choices = {
            {
                label = "Work through it.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 12 },
                success = {
                    text = "You work, and sweat, and wake up on the fourth morning clear-headed, which is "
                        .. "the way it goes for most people and is not how it feels at the time. The work "
                        .. "is done. Nobody knows what it cost, including you.",
                    deltas = { coin = 15, health = -6, attr = { VIT = 1 } },
                },
                failure = {
                    text = "You are on your back for a fortnight, and the work is not done, and someone "
                        .. "who owed you nothing does it. When you can stand again you are thinner and "
                        .. "weaker than you were, and the season has moved on without asking you.",
                    deltas = { health = -12, coin = -10, attr = { VIT = -1 } },
                },
            },
            {
                label = "Stay in and lose the week.",
                warn = "safe",
                text = "You take to the bed with a jug of water and let the week go. It costs you, in "
                    .. "coin and in standing, and you are up before the fortnight is out, which is not "
                    .. "true of the man two doors down.",
                deltas = { coin = -15, health = 4, attr = { WIS = 1 } },
            },
            {
                label = "Send for the woman who knows about fevers.",
                warn = "risk",
                text = "She comes, and burns something that smells like a burnt field, and charges for "
                    .. "it. You are better in three days, or you were going to be better in three days, "
                    .. "and there is no way to find out which, and she does not offer one.",
                deltas = { coin = -12, health = 6, attr = { PIE = 1 } },
            },
        },
    },

    {
        id = "R_BOUNDARY_STONE",
        title = "The Boundary",
        stage = "adulthood",
        ageMin = 20,
        ageMax = 55,
        weight = 10,
        repeatable = true,
        cooldown = 6,
        text = "The stones that mark where your ground ends have moved. Not far. Far enough that the "
            .. "strip in question is worth less than the argument would cost, and far enough that "
            .. "somebody stood in your field and did it.\n\nThis morning your neighbour is on his own "
            .. "side, working, and he has the posture of a man who is not going to look up.",
        choices = {
            {
                label = "Speak to him about it.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 12 },
                success = {
                    text = "He says the stones were always that way, and then, ten minutes in, says that "
                        .. "his father said the stones were always that way. By the end the stones are "
                        .. "back and neither of you has admitted anything, which is what a boundary is "
                        .. "for.",
                    deltas = { karma = 1, attr = { CHA = 1 } },
                },
                failure = {
                    text = "It becomes a shouting thing in front of both houses, and then a thing the "
                        .. "village has an opinion about. You keep the ground. You lose the morning, the "
                        .. "standing, and any chance of asking him for anything again.",
                    deltas = { notoriety = 1, karma = -1, attr = { CHA = -1 } },
                },
            },
            {
                label = "Move them back in the night.",
                warn = "risk",
                text = "It takes a quarter of an hour. He knows, because there is only one person it "
                    .. "could have been, and he says nothing about it, and the two of you now have a "
                    .. "kind of agreement that neither of you has agreed to.",
                deltas = { attr = { DEX = 1 }, karma = -1 },
            },
            {
                label = "Leave it.",
                warn = "safe",
                text = "The strip is a strip. For the rest of his life he is a man who took something "
                    .. "from you and knows it, which is a small power, and you spend it slowly and never "
                    .. "once mention it.",
                deltas = { attr = { WIS = 1 }, karma = 1 },
            },
        },
    },

    {
        id = "R_WET_YEAR",
        title = "The Wet Year",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 55,
        weight = 12,
        repeatable = true,
        cooldown = 4,
        text = "It rains through the week the cutting should have been done, and then through the week "
            .. "after that, and the grain in the low field goes grey and starts to smell sweet.\n\n"
            .. "There is a man from the next village buying early and cheap, and there is a man in the "
            .. "market town who might buy nothing at all in a month, and both of them are at the ends of "
            .. "roads you can only walk down once.",
        choices = {
            {
                label = "Sell it now, cheap.",
                warn = "safe",
                text = "You get less than it is worth and you get it today, and the coin is in the house "
                    .. "where the winter cannot take it. What is ruined then is somebody else's problem, "
                    .. "which is a sentence you would rather not have thought.",
                deltas = { coin = 20, attr = { WIS = 1 } },
            },
            {
                label = "Hold it and hope for a dry month.",
                warn = "risk",
                text = "The month is not dry. Half of it is fit for nothing and the other half goes for "
                    .. "what you were offered in the first place, less the cost of the cart, and you "
                    .. "spend the winter doing the arithmetic on the difference.",
                deltas = { coin = -15, attr = { LUK = 1, WIS = 1 } },
            },
            {
                label = "Buy in from the village that had a dry week.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "You buy low from people who do not know what the market town will pay, and "
                        .. "you are right about what the market town will pay. It is not a proud way to "
                        .. "make money and it works, and it is the first time you have done something "
                        .. "the neighbours cannot quite copy.",
                    deltas = { coin = 45, attr = { INT = 1 }, karma = -1 },
                },
                failure = {
                    text = "You buy in and the price does not move, and the grain you bought sits in a "
                        .. "barn beside the grain you grew. You have tied up everything you had in the "
                        .. "one thing that was never going to hold its value, and you know it before "
                        .. "anyone else does.",
                    deltas = { coin = -35, attr = { INT = 1 } },
                },
            },
        },
    },

    {
        id = "R_CARRY_THIS",
        title = "A Small Thing to Carry",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 55,
        weight = 10,
        repeatable = true,
        cooldown = 7,
        text = "The man has a good coat and clean hands and he has picked you out of the people at the "
            .. "toll-house, which took him a while, which means he watched first.\n\nHe wants a bundle "
            .. "carried past the gate as part of your own load. He is paying like it is heavy. It is not "
            .. "heavy. He does not say what is in it and he does not say not to look, and he is watching "
            .. "to see whether you ask.",
        choices = {
            {
                label = "Refuse.",
                warn = "safe",
                text = "He takes it back without any change in his face, and by the time you are through "
                    .. "the gate he is talking to somebody else in the same easy way. Whatever the bundle "
                    .. "carried goes through, that afternoon, and it is not on you.",
                deltas = { karma = 1, attr = { WIS = 1 } },
            },
            {
                label = "Carry it and do not look.",
                warn = "risk",
                text = "The gate is the gate and nobody stops you, and the coin is more than a month of "
                    .. "the honest kind. You will see him twice more in your life, both times in crowds, "
                    .. "and both times he will look through you.",
                deltas = { coin = 45, karma = -2, notoriety = 1 },
            },
            {
                label = "Carry it, and open it where nobody can see.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 13 },
                success = {
                    text = "It is what you expected it to be, which is nothing that would hang you and "
                        .. "nothing you want to be holding. You keep the knowledge and you keep your "
                        .. "face shut, and you come back and ask him for the same rate again, and he "
                        .. "pays it, because he now has a reason to.",
                    deltas = { coin = 45, karma = -1, notoriety = 1, attr = { WIS = 1 } },
                },
                failure = {
                    text = "You look, and you do it badly, and he notices, and the payment is short. "
                        .. "Worse: you now know a face and a trade, and he knows that you know, and that "
                        .. "is a thing that only runs one way.",
                    deltas = { coin = 15, notoriety = 2, karma = -1, attr = { WIS = 1 } },
                },
            },
        },
    },

    {
        id = "R_MOTHERS_HANDS",
        title = "Your Mother's Hands",
        stage = "adulthood",
        ageMin = 25,
        ageMax = 55,
        weight = 10,
        repeatable = true,
        cooldown = 8,
        text = "Her hands have stopped being able to do the fine work, and she has started leaving the "
            .. "hard work half-done and saying nothing about it, which from her is a kind of "
            .. "announcement.\n\nShe has not asked. She has cleaned your house twice this month, badly, "
            .. "as a way of being useful in the argument she is having with herself.",
        choices = {
            {
                label = "Take her in.",
                warn = "safe",
                text = "She moves her things in over three trips and complains about the ceiling for a "
                    .. "year. It costs you a room you were using and a standing you were building, and "
                    .. "some mornings she is well and the house is warm, and that is the whole of it.",
                deltas = { coin = -20, karma = 2, attr = { WIS = 1 } },
            },
            {
                label = "Send coin every month and visit.",
                warn = "safe",
                text = "You are careful, and dutiful, and you are not there. She tells the neighbours "
                    .. "about the coin, in a voice that has been arranged for their benefit, and you "
                    .. "hear about it later, which is the arrangement she chose.",
                deltas = { coin = -15, karma = 1 },
            },
            {
                label = "Let whoever is nearest do it.",
                warn = "risk",
                text = "Somebody handles it, since somebody always handles it, and the somebody is not "
                    .. "you, and it gets handled in a way you would not have chosen. You find out at the "
                    .. "funeral what was decided, and by then the only useful thing left to say is that "
                    .. "you were busy.",
                deltas = { karma = -2, attr = { WIS = 1 } },
            },
        },
    },

    {
        id = "R_WHAT_IS_OWED",
        title = "What Is Owed",
        stage = "adulthood",
        ageMin = 22,
        ageMax = 55,
        weight = 10,
        repeatable = true,
        cooldown = 6,
        text = "Somebody comes asking for help, and they have a claim on you: an afternoon, a debt, a "
            .. "time you were carried when you could not walk. They do not spell it out. They do not "
            .. "have to, and they know they do not have to, and that is the thing they are relying on.\n\n"
            .. "What they need is more than you have loose.",
        choices = {
            {
                label = "Give them what they ask.",
                warn = "safe",
                text = "You give it, and it is not convenient, and it goes the way most of these go: it "
                    .. "is not paid back and it is not mentioned again. Something in the account between "
                    .. "you is quiet after this, and quiet is the point of it.",
                deltas = { coin = -25, karma = 2 },
            },
            {
                label = "Give them less, and say why.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "You name a number and the reason, plainly, without dressing it up, and they "
                        .. "take it and go; the amount was never the thing they came for. That is a door "
                        .. "you can use again, and you will, and so will they.",
                    deltas = { coin = -12, karma = 1, attr = { CHA = 1 } },
                },
                failure = {
                    text = "The number sounds like a verdict when you say it out loud, and they hear it "
                        .. "as one. They take it, and it is the last time either of you pretends there "
                        .. "is an account.",
                    deltas = { coin = -12, karma = -1, attr = { WIS = 1 } },
                },
            },
            {
                label = "Say you cannot.",
                warn = "risk",
                text = "You cannot, or you have decided you cannot, and you do not fully know which, and "
                    .. "that is the part that will come back on the third night of some later week like "
                    .. "this one.",
                deltas = { karma = -2, attr = { WIS = 1 } },
            },
        },
    },

    ------------------------------------------------------------------- old age
    {
        id = "R_COLD_GETS_IN",
        title = "The Cold Gets In",
        stage = "adulthood",
        ageMin = 56,
        ageMax = 999,
        weight = 12,
        repeatable = true,
        cooldown = 4,
        text = "The house has a draught that was not there last year, or your blood is thinner than it "
            .. "was, and the two were always going to meet in a room like this one.\n\nYou are stiff in "
            .. "the morning now in a way that has to be waited out, and there is a stack of wood by the "
            .. "shed that has to become a stack of wood by the fire, and there is nobody else in the "
            .. "house who is going to do it.",
        choices = {
            {
                label = "Keep the fire small and stay near it.",
                warn = "safe",
                text = "You burn less and sit closer. The winter is long and boring and survivable, "
                    .. "which is a description that has come to fit a lot of things.",
                deltas = { health = 2, coin = -5, attr = { WIS = 1 } },
            },
            {
                label = "Go out for the wood anyway.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 12 },
                success = {
                    text = "You bring it in in three loads instead of one and stop between each. Nothing "
                        .. "happens. That is what you say when it is asked, and it is true, and it is not "
                        .. "the whole of the answer.",
                    deltas = { health = -2, attr = { VIT = 1, WIS = 1 } },
                },
                failure = {
                    text = "You are on the ground by the pile for a while before you are up again, and "
                        .. "the cold you catch out there does not leave as quickly as it came. You tell "
                        .. "people it was the ice.",
                    deltas = { health = -10, attr = { VIT = -1 } },
                },
            },
            {
                label = "Ask the young family next door.",
                warn = "risk",
                text = "They come, and are kind, and are also working out what the arrangement is and "
                    .. "what it might one day be worth. Both things are true. You take the wood and you "
                    .. "let them have the calculation, and you do not sleep well about it.",
                deltas = { coin = -10, karma = 1, health = 3, attr = { WIS = 1 } },
            },
        },
    },

    {
        id = "R_WHAT_TO_LEAVE",
        title = "What to Do With the House",
        stage = "adulthood",
        ageMin = 58,
        ageMax = 999,
        weight = 10,
        repeatable = true,
        cooldown = 9,
        text = "The house is worth more than you thought it was, which you have learned from a man who "
            .. "came round about it, and which he was careful not to say too plainly.\n\nThe people who "
            .. "would have it have not been to see you in some time, and there is a version of this "
            .. "where it goes while you are alive and you get to see what they do with it.",
        choices = {
            {
                label = "Leave it to whoever stayed near.",
                warn = "safe",
                text = "You write it down plainly and give the paper to the priest to keep. It is not a "
                    .. "surprise to anyone except the ones who might have expected otherwise, and you "
                    .. "say the true reason out loud once, and then never again.",
                deltas = { karma = 2, coin = -5, attr = { WIS = 1 } },
            },
            {
                label = "Sell it while you can.",
                warn = "risk",
                text = "You take the coin and the coin is real, and the family have opinions about a "
                    .. "house they did not visit being sold out from under a memory. You are comfortable "
                    .. "at the end of a life spent not being, which is a strange shape for a reward, and "
                    .. "you have decided to accept it.",
                deltas = { coin = 60, karma = -2 },
            },
            {
                label = "Change nothing.",
                warn = "safe",
                text = "The house stays yours and you keep knowing where the loose board is. Nothing is "
                    .. "said and nothing is done and the question simply gets handed to whoever comes "
                    .. "after, to have on whatever day it lands.",
                deltas = { attr = { WIS = 1 } },
            },
        },
    },

    {
        id = "R_SOMEONE_FROM_BEFORE",
        title = "Someone From Before",
        stage = "adulthood",
        ageMin = 56,
        ageMax = 999,
        weight = 10,
        repeatable = true,
        cooldown = 6,
        text = "You have not seen the face in forty years and you know it in less than a second, in a "
            .. "market, over the price of onions.\n\nThere is a thing between you that was never settled "
            .. "and that everyone involved has been letting lie. They have seen you too. They are "
            .. "deciding what to do with their hands.",
        choices = {
            {
                label = "Go over and say the thing.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 12 },
                success = {
                    text = "You say it badly and they hear it anyway. You end up standing between the "
                        .. "stalls for the length of a long story about a brother you never met, and then "
                        .. "you part, and the thing is not fixed, and it is settled.",
                    deltas = { karma = 2, attr = { WIS = 1, CHA = 1 } },
                },
                failure = {
                    text = "The words come out in the wrong order and land as an excuse, which is what "
                        .. "they have been, partly, all along. They nod the way people nod at a stranger, "
                        .. "and pick up their onions, and the thing stays where it was.",
                    deltas = { attr = { WIS = 1 } },
                },
            },
            {
                label = "Let them not have seen you.",
                warn = "safe",
                text = "You look at the onions until they are done and gone. There is time, afterwards, "
                    .. "to notice that this is the third time you have chosen the same way of handling "
                    .. "it, and that the first two are both still in the room with you.",
                deltas = { attr = { WIS = 1 }, karma = -1 },
            },
            {
                label = "Buy their onions for them.",
                warn = "risk",
                text = "You pay the stall and walk off before they can refuse, which is the kind of "
                    .. "gesture that cannot be answered. It settles nothing. It does mean that "
                    .. "afterwards, when one of you is being remembered badly by somebody, the other "
                    .. "one says less than they could.",
                deltas = { coin = -8, karma = 1, attr = { LUK = 1 } },
            },
        },
    },
}

local function statValue(state, key)
    if state.attrs and state.attrs[key] ~= nil then
        return state.attrs[key]
    end
    local resources = {
        health = state.health,
        mana = state.mana,
        level = state.level,
        exp = state.exp,
        coin = state.coin,
        karma = state.karma,
        notoriety = state.notoriety,
        age = state.age,
    }
    return resources[key]
end

Events.statValue = statValue

--- Does this event's `requires` block pass for this character? ALL must pass.
function Events.isEligible(event, state)
    local age = state.age or 0
    if event.ageMin and age < event.ageMin then
        return false
    end
    if event.ageMax and age > event.ageMax then
        return false
    end

    local req = event.requires
    if req then
        if req.race then
            local ok = false
            for _, raceId in ipairs(req.race) do
                if raceId == state.raceKey then
                    ok = true
                    break
                end
            end
            if not ok then
                return false
            end
        end

        if req.flags then
            for _, flag in ipairs(req.flags) do
                if not state.flags[flag] then
                    return false
                end
            end
        end

        if req.notFlags then
            for _, flag in ipairs(req.notFlags) do
                if state.flags[flag] then
                    return false
                end
            end
        end

        for key, minimum in pairs(req.minStat or {}) do
            local value = statValue(state, key)
            if value == nil or value < minimum then
                return false
            end
        end

        for key, maximum in pairs(req.maxStat or {}) do
            local value = statValue(state, key)
            if value ~= nil and value > maximum then
                return false
            end
        end
    end

    return true
end

--- Draw weight for an event: base weight, softened at the edges of its age
--- band, boosted 1.5x for race-specific content (design brief §4.3).
function Events.weight(event, state)
    local weight = event.weight or 10
    -- Repeatable generics are held apart by `cooldown` instead; trimming their
    -- edges as well would only make the band's first and last years thinner.
    if not event.repeatable and event.ageMin and event.ageMax and event.ageMax > event.ageMin then
        local span = event.ageMax - event.ageMin
        local into = (state.age or 0) - event.ageMin
        local edge = math.min(into, span - into)
        if edge < span * 0.2 then
            weight *= 0.3 -- the very first or last years of the band
        elseif edge < span * 0.4 then
            weight *= 0.6
        end
    end
    if event.requires and event.requires.race then
        weight *= 1.5
    end
    return weight
end

--- The authored-tier pool: events that fire once a run and never again. These
--- are the beats of a life, and one of them being eligible outranks any generic.
function Events.authoredPool(state)
    local pool = {}
    for _, event in ipairs(Events.All) do
        if not event.chainOnly and not event.repeatable and not state.fired[event.id] then
            if Events.isEligible(event, state) then
                table.insert(pool, event)
            end
        end
    end
    return pool
end

--- The repeatable tier for this age. Unless `ignoreCooldown` is set, an entry
--- that fired within its cooldown window is not in the pool — which is the whole
--- difference between texture and a loop.
function Events.repeatablePool(state, ignoreCooldown)
    local pool = {}
    for _, event in ipairs(Events.Repeatable) do
        if Events.isEligible(event, state) then
            local last = state.firedAt and state.firedAt[event.id]
            local cooldown = event.cooldown or Config.EventDraw.cooldownDefault
            if ignoreCooldown or last == nil or (state.age or 0) - last >= cooldown then
                table.insert(pool, event)
            end
        end
    end
    return pool
end

--- Everything this character can currently draw from: both tiers.
function Events.pool(state)
    local pool = Events.authoredPool(state)
    for _, event in ipairs(Events.repeatablePool(state)) do
        table.insert(pool, event)
    end
    return pool
end

function Events.byId(id)
    for _, event in ipairs(Events.All) do
        if event.id == id then
            return event
        end
    end
    for _, event in ipairs(Events.Repeatable) do
        if event.id == id then
            return event
        end
    end
    return nil
end

--- The odds that a year the authored tier did not claim still offers a card.
--- Bands come from Config.EventDraw; an age no band covers (infancy) is 0.
function Events.cardChance(state)
    local age = state.age or 0
    for _, band in ipairs(Config.EventDraw.repeatChance) do
        if age <= band.maxAge then
            return band.chance
        end
    end
    return 0
end

--- Weighted draw for one year. Returns nil for a quiet year — which is a line,
--- not a blank, and is a deliberate outcome at every age.
---
--- Order: an eligible authored event wins the year outright; otherwise the
--- repeatable tier gets one roll against the age band's chance; otherwise quiet.
--- If every generic for this age is still cooling, the cooldown is relaxed to
--- its coldest entry, so an adult year is never silent for want of content.
function Events.draw(state, rng)
    local authored = Events.authoredPool(state)
    if #authored > 0 then
        return Rng.weighted(rng, authored, function(event)
            return Events.weight(event, state)
        end)
    end

    if not Rng.chance(rng, Events.cardChance(state)) then
        return nil
    end

    local pool = Events.repeatablePool(state)
    if #pool == 0 and Config.EventDraw.respectCooldownAsFloor then
        pool = Events.repeatablePool(state, true)
    end
    if #pool == 0 then
        return nil
    end
    return Rng.weighted(rng, pool, function(event)
        return Events.weight(event, state)
    end)
end

--- Queue-stored chain events. Each entry is { id = "...", atAge = n }.
function Events.dueChain(state)
    for index, entry in ipairs(state.chainQueue) do
        if (state.age or 0) >= entry.atAge then
            local event = Events.byId(entry.id)
            if event then
                table.remove(state.chainQueue, index)
                return event
            end
            table.remove(state.chainQueue, index)
            return Events.dueChain(state)
        end
    end
    return nil
end

return Events
