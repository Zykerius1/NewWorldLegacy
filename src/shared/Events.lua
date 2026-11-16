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

    ---------------------------------------------------------------- childhood
    -- COMBAT LEAD 1. Enemy: a dog gone to the hills. Tests DEX or STR.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_WOLF_AT_THE_FOLD",
        title = "What Came to the Fold",
        stage = "childhood",
        ageMin = 9,
        ageMax = 12,
        weight = 10,
        text = "Something has been at the fold twice, and the second time it took a lamb and left the skin, "
            .. "which is not how a dog eats. Your father is at the far field and will not be back before dark, "
            .. "and the fold gate is a hurdle you could lift, and the thing is in the hedge line again, and it "
            .. "is not hurrying.",
        choices = {
            {
                label = "Get the lamb inside and drop the hurdle behind you.",
                warn = "[DEX]",
                check = { attr = "DEX", dc = 12 },
                success = {
                    text = "You are through the gate with it in your arms and your shoulder against the hurdle "
                        .. "before the thing has finished deciding. It stands in the gap for a while, looking at "
                        .. "the wood, and then it goes. In the morning there is one lamb more than there would "
                        .. "have been, and nobody asks how.",
                    deltas = { attr = { DEX = 2 }, exp = 30, karma = 1, flags = { "held_the_fold" } },
                },
                failure = {
                    text = "It is in the fold before you are, and it does not want the lamb any more, because "
                        .. "you are nearer. Your arm takes the worst of it and your father finds you sitting "
                        .. "against the hurdle with the dog's shape already gone up the hill. He does not ask "
                        .. "what you thought you were doing, which is worse than asking.",
                    deltas = { health = -26, healthMaxAdjust = -6, attr = { DEX = 1, WIS = 1 }, karma = 1 },
                },
            },
            {
                label = "Stand in the gap and shout until the lane comes.",
                warn = "[STR]",
                check = { attr = "STR", dc = 11 },
                success = {
                    text = "You make a noise a boy should not be able to make and you keep making it, and the "
                        .. "thing goes along the hedge rather than through you, and the neighbour arrives with a "
                        .. "fork and a great deal to say. By the morning it is a story. It was not a story.",
                    deltas = { attr = { STR = 1, CHA = 1 }, karma = 2, notoriety = 1, flags = { "held_the_fold" } },
                },
                failure = {
                    text = "Your voice goes early and the noise is a boy's noise and the thing knows it. It comes "
                        .. "at the gap and you get out of it, mostly, and the lamb does not. Your father counts "
                        .. "the fold twice in the morning and says nothing about the counting.",
                    deltas = { health = -14, attr = { WIS = 1 }, karma = -1 },
                },
            },
            {
                label = "Take the hay fork into the hedge after it.",
                warn = "risk",
                text = "You go in after it with a fork and a lamp and no plan at all, and the hedge is not thick "
                    .. "enough to hide anything and it hides it anyway. You get one good thrust into something "
                    .. "that is not where you thought it was. The lane talks about it for a month. You are not "
                    .. "sure, afterwards, which of you left first.",
                deltas = { health = -12, attr = { DEX = 1, STR = 1 }, exp = 60, notoriety = 2, karma = 1 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_GOAT_ARGUMENT",
        title = "The Goat and the Hedge",
        stage = "childhood",
        ageMin = 5,
        ageMax = 9,
        weight = 12,
        text = "The hedge between your family's ground and the next is gone along a length of it, and the "
            .. "neighbour's goat is standing in the gap with the evidence on its face. The neighbour says the "
            .. "hedge was always thin. Your father says the goat was always a thief. Both of them have been "
            .. "saying it for three days now, in the lane, in front of anyone who will stand still.",
        choices = {
            {
                label = "Say what you saw, in front of everyone.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "You say it plainly and you say it once, and the lane goes quiet in the way that means "
                        .. "it has decided. The neighbour takes his goat home by the collar and your father does "
                        .. "not thank you until much later, in the yard, badly.",
                    deltas = { attr = { CHA = 1 }, karma = 1, flags = { "goat_witness" } },
                },
                failure = {
                    text = "You say it and your voice does the thing voices do at that age, and the neighbour "
                        .. "laughs, and the laughing is the end of it. Your father takes you inside with a hand "
                        .. "on your shoulder that is heavier than it needs to be.",
                    deltas = { attr = { CHA = -1, WIS = 1 }, karma = -1 },
                },
            },
            {
                label = "Say the hedge was thin, and let it go.",
                warn = "safe",
                text = "You say the hedge was thin. It was not thin. Your father hears you say it and looks at "
                    .. "you for a while, and the argument ends in the lane's favour, which is nobody's favour, and "
                    .. "the goat stays where it is. The ground is the ground and it is still there.",
                deltas = { karma = -1, attr = { WIS = 1 }, flags = { "hedge_conceded" } },
                next = "E_THE_GOAT_THAT_WAS_OWED",
                delayYears = 24,
            },
            {
                label = "Take the goat back in the night.",
                warn = "risk",
                text = "You are out of the house and back in it before the lamp next door is lit, and the goat "
                    .. "comes with you because goats will follow anything that is walking away. It is in your "
                    .. "field in the morning. There is only one person it could have been and the lane is "
                    .. "unanimous about which.",
                deltas = { coin = 8, karma = -2, attr = { DEX = 1 }, notoriety = 1 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_BOARD_BY_THE_SHRINE",
        title = "The Board by the Shrine",
        stage = "childhood",
        ageMin = 8,
        ageMax = 12,
        weight = 10,
        text = "There is a board by the shrine with the grain price chalked on it, and it is changed on days "
            .. "nobody can predict, and your mother cannot read it and will not say so. She sends you with the "
            .. "cart money and a sentence she has rehearsed in the yard. The chalk says one thing and the man "
            .. "with the sacks says another, and both of them are looking at you to be the one who decides.",
        choices = {
            {
                label = "Read the board out loud and pay what it says.",
                warn = "[INT]",
                check = { attr = "INT", dc = 10 },
                success = {
                    text = "You read it out and the man with the sacks hears his own board said back to him in a "
                        .. "child's voice, and something in the way he fills the sack changes. You come home with "
                        .. "the grain and the change and your mother counts it twice, and then a third time.",
                    deltas = { attr = { INT = 1 }, coin = 5, karma = 1 },
                },
                failure = {
                    text = "You get a word wrong, and the man with the sacks is kind about it, which is the "
                        .. "expensive kind of kindness. You pay what he says. On the way home you work out what "
                        .. "the board actually said, and you keep working it out for a mile.",
                    deltas = { attr = { INT = 1, WIS = 1 }, coin = -8 },
                },
            },
            {
                label = "Pay the man and say nothing.",
                warn = "safe",
                text = "You pay and say nothing and carry the sack home, and your mother does not ask what the "
                    .. "board said, because asking would mean she could not read it. It costs a little more than "
                    .. "it should and it costs nobody anything else.",
                deltas = { coin = -10, attr = { WIS = 1 } },
            },
            {
                label = "Walk to the next village and buy there.",
                warn = "risk",
                text = "It is further than it looks and the sack is heavier on the way back than it was going, "
                    .. "and you are late, and the lane has been looking for you. The grain is better and there is "
                    .. "more of it. Your mother is angry in the way people are angry when they have been "
                    .. "frightened.",
                deltas = { coin = 4, health = -4, attr = { LUK = 1, WIS = 1 } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_SMOKE_ON_THE_PLAIN",
        title = "The Smoke That Does Not Move",
        stage = "childhood",
        ageMin = 6,
        ageMax = 11,
        weight = 10,
        text = "There is smoke standing up off the plain where there is no fire and no house, and it has been "
            .. "there since the spring, and it does not lean with the wind. Adults have started calling it the "
            .. "weather. Your mother has started shutting the shutter on that side of the house, which is not "
            .. "the same as calling it the weather.",
        choices = {
            {
                label = "Go up on the roof and look at it properly.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 12 },
                success = {
                    text = "From the roof you can see that the smoke is not smoke, and that it is not going up so "
                        .. "much as standing, and that the plain under it has gone the colour of a wet slate. You "
                        .. "come down and tell nobody, because there is no sentence for it that an adult will "
                        .. "accept from you.",
                    deltas = { attr = { WIS = 2 }, health = -3, flags = { "saw_the_tomb" } },
                },
                failure = {
                    text = "The thatch gives where the rain has been getting in and you go through it, and the "
                        .. "fall is not the bad part. The bad part is your mother's face when she comes out, "
                        .. "because she had been keeping the shutter shut for a reason and now she has to say it.",
                    deltas = { health = -8, attr = { WIS = 1 }, karma = 1 },
                },
            },
            {
                label = "Tell the priest what you saw.",
                warn = "safe",
                text = "The priest listens with his hands folded and then says something careful about the plain, "
                    .. "and you understand that he has already been told and has already decided what to say. He "
                    .. "gives you a sweet from a jar he keeps for children and asks after your mother by name.",
                deltas = { karma = 2, attr = { PIE = 1 }, flags = { "told_the_shrine" } },
            },
            {
                label = "Do as the house does and shut it out.",
                warn = "safe",
                text = "You stop looking at that side of the house. It is not difficult. By the end of the month "
                    .. "you have to be reminded which way the shutter faces, and the reminder is the first time "
                    .. "you notice that this is a thing a whole village can do at once.",
                deltas = { attr = { WIS = 1 }, flags = { "kept_it_shut" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_BREAD_CUT_THIN",
        title = "The Bread Cut Thin",
        stage = "childhood",
        ageMin = 3,
        ageMax = 9,
        weight = 12,
        text = "The loaf is cut thinner than it was and nobody has said why, and your mother has started eating "
            .. "after everyone else, which means she is eating what is left. This morning you counted the cuts "
            .. "on the board. She saw you counting and did not tell you off, and that is the part you keep.",
        choices = {
            {
                label = "Say you are not hungry and leave half of it.",
                warn = "safe",
                text = "You leave it on the board and go out, and when you come back in it is gone, and she does "
                    .. "not mention it, and you are hungry all morning in a way that is somehow not the worst "
                    .. "thing in the house.",
                deltas = { health = -4, karma = 2, attr = { WIS = 1 } },
            },
            {
                label = "Eat it and say nothing.",
                warn = "risk",
                text = "You eat it and it is not enough and you say nothing about that either, and you learn "
                    .. "early that a house can be hungry and quiet at the same time, and that the quiet is a "
                    .. "decision somebody is making every morning.",
                deltas = { health = 2, karma = -1, attr = { WIS = 1 } },
            },
            {
                label = "Take the crust over to her.",
                warn = "safe",
                text = "She says she has eaten. She has not eaten. You put it in her hand and close her fingers "
                    .. "over it, which is a thing you have seen her do to other people, and she looks at you as "
                    .. "though a stranger has come into the room.",
                deltas = { karma = 3, attr = { PIE = 1 }, health = -3 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_COLUMN_AT_THE_WELL",
        title = "The Column at the Well",
        stage = "childhood",
        ageMin = 7,
        ageMax = 12,
        weight = 10,
        text = "The column comes up the lane in the middle of the day and stops at the well without asking, and "
            .. "there are more of them than the village has buckets. Their colours are the ones nobody had a name "
            .. "for a year ago and their boots are new. One of them, who is not much older than your brother, "
            .. "holds out a copper and points at the water, and every adult on the lane is looking at you "
            .. "because you are nearest.",
        choices = {
            {
                label = "Take the coin and fill the bucket.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "You fill it and he drinks and then he says something to the man behind him and they "
                        .. "both laugh, and it is not a cruel laugh, and one of them gives you a second copper "
                        .. "for nothing. The lane decides you handled it well. Nobody asks you how.",
                    deltas = { coin = 6, attr = { CHA = 1 }, notoriety = 1 },
                },
                failure = {
                    text = "You take the coin and then you cannot make the bucket work with everyone watching, and "
                        .. "the water goes over your feet, and a man further back in the column says something "
                        .. "short. The soldier takes the bucket off you himself and does it, and does not take the "
                        .. "coin back, which is the worst arrangement available.",
                    deltas = { coin = 3, attr = { WIS = 1 }, health = -2 },
                },
            },
            {
                label = "Fill it and give it to him without the coin.",
                warn = "safe",
                text = "You fill it and put it in his hands and step back, and he looks at the copper and then at "
                    .. "you and puts it away. The column goes on up the lane. An old woman two doors down says "
                    .. "something about your mother that is not a compliment and is not entirely an insult.",
                deltas = { karma = 2, attr = { PIE = 1 }, flags = { "water_to_the_column" } },
            },
            {
                label = "Say the well is dry.",
                warn = "risk",
                text = "You say the well is dry and the soldier looks at the full trough and the wet stones and "
                    .. "then at you, and decides, for reasons of his own, to let it be a child's lie. He fills his "
                    .. "own bucket. The column is in the lane for an hour and nobody in the village drinks "
                    .. "anything until it has gone.",
                deltas = { attr = { CHA = 1 }, karma = -1, notoriety = 2, flags = { "lied_to_the_column" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_WHAT_TO_CALL_IT",
        title = "What to Call It",
        stage = "childhood",
        ageMin = 6,
        ageMax = 10,
        weight = 9,
        text = "The baby came in the night and the women have been in the room since, and the priest has not "
            .. "been sent for, because the priest costs a coin and the coin is not there. Your father is sitting "
            .. "in the yard with his hands on his knees. He asks you what it should be called, and it is not a "
            .. "joke, and he does not look up when he asks it.",
        choices = {
            {
                label = "Name it after the one who died.",
                warn = "safe",
                text = "He is quiet for a long time and then he says it out loud once, testing it, and then he "
                    .. "goes in and says it to your mother through the door. Nobody in the house uses the name "
                    .. "carelessly after that, and the child grows up carrying a person it never met.",
                deltas = { karma = 2, attr = { WIS = 1 }, flags = { "named_the_child" } },
            },
            {
                label = "Name it something this family has never used.",
                warn = "risk",
                text = "He looks up at that, and something crosses his face that you will understand much later, "
                    .. "when you have children and someone suggests a name to you. He says it is a good name. The "
                    .. "lane says the child is named for nobody, which in this lane is a thing to say.",
                deltas = { attr = { CHA = 1 }, notoriety = 1, karma = -1, flags = { "named_the_child" } },
            },
            {
                label = "Say it is the priest's business.",
                warn = "safe",
                text = "He nods slowly, as though you have said something wise instead of something frightened, "
                    .. "and the coin is found from somewhere, and the priest comes and does the small rite and "
                    .. "writes a name in the book that nobody in the family chose.",
                deltas = { coin = -5, attr = { PIE = 1 }, karma = 1 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_SLATES_AND_THE_SEAL",
        title = "The Slates and the Seal",
        stage = "childhood",
        ageMin = 7,
        ageMax = 11,
        weight = 10,
        text = "A man has come from the district with a box of slates and permission, which is the part the "
            .. "village cannot get past. He will teach letters to any child who can be spared from the field, in "
            .. "the mornings, for nothing. He is very patient, and he is writing down every name that comes to "
            .. "the door, on paper with a seal on it that nobody here has seen before.",
        choices = {
            {
                label = "Go, and learn to read.",
                warn = "[INT]",
                check = { attr = "INT", dc = 10 },
                success = {
                    text = "By the end of the season you can read the levy notice on the shrine door, and the "
                        .. "notice is not what the village has been told it says. You keep that to yourself for "
                        .. "about a week, which at your age is a very long time.",
                    deltas = { attr = { INT = 2 }, flags = { "reads_the_notices" } },
                },
                failure = {
                    text = "The letters will not stay the right way round and the man is patient about it in a "
                        .. "way that makes you not want to go back. You go back. By the end you can write your own "
                        .. "name and read half of somebody else's, and the seal is on the paper either way.",
                    deltas = { attr = { INT = 1, WIS = 1 }, notoriety = 1 },
                },
            },
            {
                label = "Go, and give a name that is not yours.",
                warn = "risk",
                text = "The man writes it down without looking up and you spend a season being somebody else on "
                    .. "paper and yourself in the room. It is the first lie you have told that had to be "
                    .. "maintained daily, and you are surprised to find that you are good at maintaining things.",
                deltas = { attr = { INT = 1, LUK = 1 }, karma = -1, flags = { "false_name_on_the_roll" } },
            },
            {
                label = "Stay in the field.",
                warn = "safe",
                text = "There is work and the work is real and the letters are a thing the district wants, not a "
                    .. "thing the house needs. You are in the field all that season and your hands harden and the "
                    .. "man with the slates goes away at the end of it, taking the paper with the seal with him.",
                deltas = { coin = 6, attr = { STR = 1 }, health = -2 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_A_PENNY_A_TAIL",
        title = "A Penny a Tail",
        stage = "childhood",
        ageMin = 8,
        ageMax = 12,
        weight = 9,
        text = "The shrine pays a penny a tail and every child in the lane has been in the barns since, and the "
            .. "tails are getting harder to find, and then the miller's boy shows you where they come from. "
            .. "There is a shed behind the mill with a floor of old straw and a smell that gets into your clothes "
            .. "and stays. He says his father does not know. The way he says it means his father knows.",
        choices = {
            {
                label = "Take the tails and say nothing.",
                warn = "risk",
                text = "You go in with him twice a week and come out with more tails than any child in the lane, "
                    .. "and the pennies are real, and the shrine's man starts to look at you for a moment before "
                    .. "he counts. There is a thing you are now part of and it has a floor of straw and a smell.",
                deltas = { coin = 10, karma = -2, attr = { LUK = 1 } },
            },
            {
                label = "Tell the priest where they come from.",
                warn = "safe",
                text = "The priest listens and does not look surprised, and the shed is gone within the month and "
                    .. "so is the penny a tail, which nobody thanks you for. The miller knows who said it. He is "
                    .. "polite to your family for the rest of his life in a way that is not politeness.",
                deltas = { karma = 3, attr = { PIE = 1 }, notoriety = 2, flags = { "crossed_the_miller" } },
            },
            {
                label = "Take the boy's work and split the pennies.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "You do the shed and he does the shrine and the arithmetic works out better for both "
                        .. "of you, and it works for two seasons. He is the first person you have ever had an "
                        .. "arrangement with rather than a fight with, and it turns out you like arrangements.",
                    deltas = { coin = 8, attr = { CHA = 1 }, karma = 1 },
                },
                failure = {
                    text = "He agrees and then does not do the shrine, and you are the one holding the tails when "
                        .. "the priest's man asks where they came from. You take the shorter end of it. He is "
                        .. "still your friend, which you find you mind more than the money.",
                    deltas = { coin = 4, attr = { WIS = 1 }, karma = -1 },
                },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_CROSSROADS",
        title = "The Crossroads",
        stage = "childhood",
        ageMin = 10,
        ageMax = 12,
        weight = 8,
        text = "They hanged a man at the crossroads for taking grain out of a cart, and he has been up there "
            .. "since the morning, and you are sent past it with the handcart because the road round is longer. "
            .. "He is not the first. He is the first one you have seen close. There is a woman sitting in the "
            .. "ditch on the far side who has not moved all day, and nobody has gone to her.",
        choices = {
            {
                label = "Stop the cart and sit with her.",
                warn = "safe",
                text = "You sit in the ditch and she does not look at you and after a while she starts talking "
                    .. "about a completely different year, and you listen to all of it. The cart is late home. "
                    .. "You are told off for the cart. You do not mention the ditch, and neither does she, ever.",
                deltas = { karma = 4, attr = { WIS = 1, PIE = 1 }, coin = -2 },
            },
            {
                label = "Get past it and get home.",
                warn = "safe",
                text = "You go past with your eyes on the cart's wheel and you are home in good time and the "
                    .. "errand is done properly. You will find, over the next few years, that you can still see "
                    .. "the ditch, and that you have never once been able to remember what you were carrying.",
                deltas = { attr = { WIS = 1 }, karma = -1, flags = { "walked_past" } },
            },
            {
                label = "Cut him down.",
                warn = "[DEX]",
                check = { attr = "DEX", dc = 13 },
                success = {
                    text = "It takes longer than you think and the rope is worse than the man, and when he comes "
                        .. "down the woman makes a sound you will hear for the rest of your life. The two of you "
                        .. "put him in the ditch under her cloak. The road is empty. Somebody will know by "
                        .. "evening that somebody cut him down.",
                    deltas = { karma = 6, notoriety = 6, attr = { DEX = 1 }, flags = { "cut_him_down" } },
                },
                failure = {
                    text = "You are halfway up the post when the man from the toll road comes round the bend, and "
                        .. "he is not angry, he is tired, and being handled by a tired man is worse. He takes the "
                        .. "cart and walks you home himself and tells your father a shorter version of it in the "
                        .. "yard.",
                    deltas = { health = -12, notoriety = 4, attr = { WIS = 1 }, coin = -6 },
                },
            },
        },
    },

    -------------------------------------------------------------- adolescence
    -- COMBAT LEAD 2. Enemy: a boar that has stopped running from people. Tests
    -- STR or WIS. Death possible on the first.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_BOAR_IN_THE_WOOD",
        title = "The Boar in the Oak Wood",
        stage = "adolescence",
        ageMin = 13,
        ageMax = 16,
        weight = 10,
        deathText = "the boar in the oak wood, which had stopped being afraid of people some time before",
        text = "The boar has been in the oak wood since the mast fell and it has stopped running from people, "
            .. "which is the whole of the danger. Two of the village dogs went in after it and one came out. "
            .. "Your father says leave it, and the wood is the only place the winter fuel is, and the winter is "
            .. "coming earlier than the almanac said it would.",
        choices = {
            {
                label = "Go in with the dogs and the spear.",
                warn = "[STR]",
                check = { attr = "STR", dc = 13 },
                success = {
                    text = "It comes at you along the ride and you get the spear into the shoulder and then you "
                        .. "are underneath it and then, quite suddenly, you are not. The dogs finish it. You are "
                        .. "wet to the elbows and shaking, and the meat lasts the village a fortnight and the "
                        .. "winter fuel comes home on the cart.",
                    deltas = {
                        exp = 80, coin = 25, attr = { STR = 2 }, health = -12,
                        notoriety = 2, flags = { "killed_the_boar" },
                    },
                },
                failure = {
                    text = "The spear goes in and the boar does not care. It takes you off your feet and it is "
                        .. "still coming when the light goes, and the men who come for you find the dogs first. "
                        .. "They carry you home the long way so the lane does not see it.",
                    deltas = { health = -999, flags = { "died_in_the_wood" } },
                },
            },
            {
                label = "Wait for it on the path and take it tired.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 12 },
                success = {
                    text = "You sit on the path for a long time and let it move first, and when it comes back "
                        .. "along the ride at dusk it is slower than it was at noon and it does not look up. It "
                        .. "is not a heroic way to kill a boar. It is the way that leaves you with both hands.",
                    deltas = { exp = 60, coin = 20, attr = { WIS = 1, DEX = 1 }, health = -5 },
                },
                failure = {
                    text = "You wait on the wrong path, and the light goes while you are waiting, and you come "
                        .. "out of the wood in the dark with the fuel still not cut. On the way back you fall in "
                        .. "the ditch and something in your side stays wrong for a month.",
                    deltas = { health = -18, attr = { WIS = 1 } },
                },
            },
            {
                label = "Burn the mast under the oaks and drive it out.",
                warn = "risk",
                text = "The fire does what fire does and the boar comes out of the wood in front of it, straight "
                    .. "through the village, and goes into the reeds and is not seen again. Nobody is hurt. The "
                    .. "wood is smaller than it was and will be smaller for twenty years, and the fuel problem is "
                    .. "solved by there being less to fuel.",
                deltas = { attr = { INT = 1 }, karma = -2, coin = -8, health = -6, notoriety = 2 },
            },
        },
    },

    -- COMBAT LEAD 3. Enemy: four men at the ford, pressed out of a broken levy.
    -- Tests CHA or STR. Death possible on the last.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_PRESS_GANG",
        title = "The Men at the Ford",
        stage = "adolescence",
        ageMin = 14,
        ageMax = 17,
        weight = 10,
        deathText = "the men at the ford, who had not decided anything until somebody made them decide",
        text = "There are four men at the ford with a fire and no cart, and they have been there since "
            .. "yesterday, and they are not soldiers and they are not bandits yet. They want the grain you are "
            .. "carrying and they have not decided how to want it. The one who does the talking has a guild plate "
            .. "on his chest that has been scratched at, and he keeps touching it while he speaks.",
        choices = {
            {
                label = "Give them half and walk on.",
                warn = "safe",
                text = "You give them half and they let you through and one of them says something as you pass "
                    .. "that is nearly an apology. The house is short that month and nobody asks why, and the ford "
                    .. "is empty the next time you go that way, and it is empty for years.",
                deltas = { coin = -10, karma = 1, attr = { WIS = 1 }, flags = { "paid_the_ford" } },
            },
            {
                label = "Talk them out of it.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 13 },
                success = {
                    text = "You tell them what the levy pays and what the district does to men who take grain "
                        .. "off a cart on a road with a toll bar on it, and you tell it without any heat at all. "
                        .. "The one with the plate stops touching it. They take a handful and wave you on and it "
                        .. "is the handful that makes it an arrangement rather than a robbery.",
                    deltas = { attr = { CHA = 2 }, exp = 40, karma = 1, flags = { "talked_the_ford" } },
                },
                failure = {
                    text = "You talk too long and one of the quiet ones walks round behind the cart while you are "
                        .. "doing it. They take the load and the cart and leave you the harness, and the lesson is "
                        .. "not the load. The lesson is that the man doing the talking is never the one to watch.",
                    deltas = { coin = -20, health = -12, attr = { WIS = 1 } },
                },
            },
            {
                label = "Put the cart across the ford and make them take it.",
                warn = "risk",
                check = { attr = "STR", dc = 14 },
                success = {
                    text = "You get the cart broadside in the shallow water and you stand on the near side of it "
                        .. "with the goad, and it turns out that four men who have not decided are four men who "
                        .. "will not wade. They go up the bank and along it. You are shaking for an hour "
                        .. "afterwards and you do not stop being pleased about it for years.",
                    deltas = {
                        exp = 90, coin = 10, attr = { STR = 1 }, health = -14,
                        notoriety = 4, flags = { "held_the_ford" },
                    },
                },
                failure = {
                    text = "The cart goes over in the water and the grain goes with it and the four of them come "
                        .. "across the shallows at a walk, and after that it is not a negotiation and it is not "
                        .. "quick. The ford is found the next day by a carter who tells the lane there was a "
                        .. "great deal of blood and not much of it theirs.",
                    deltas = { health = -999, flags = { "drowned_at_the_ford" } },
                },
            },
        },
    },

    -- COMBAT LEAD 4. Enemy: the hedge-witch at the village well — the caster
    -- archetype that already exists in CombatData but is unplaced. Tests WIS or
    -- PIE. Death possible on the second.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_HEDGE_WITCH_WELL",
        title = "The Light at the Well",
        stage = "adolescence",
        ageMin = 16,
        ageMax = 17,
        weight = 9,
        deathText = "the light at the well, which was not a lantern, and the woman who was holding it",
        text = "The woman at the edge of the village has been drawing from the well at night since the water "
            .. "went strange, and the well is the village's and she is not. Two households have said what they "
            .. "think and one of them has said it to the shrine. Tonight there is a light at the well and it is "
            .. "the wrong colour, and it is not a lantern, and somebody has to go and say something to her.",
        choices = {
            {
                label = "Go down and tell her to draw somewhere else.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 12 },
                success = {
                    text = "You walk down with your hands where she can see them and you say it plainly and you "
                        .. "do not once say the word the shrine uses for her. She looks at you for a while and "
                        .. "then she laughs, and it is a real laugh, and she says the water will be sweet again by "
                        .. "the thaw and that you are the only one who has come down to ask.",
                    deltas = { attr = { WIS = 2 }, karma = 1, flags = { "spoke_to_the_witch" } },
                },
                failure = {
                    text = "You get as far as the third stone and then your mouth is dry and your legs are not "
                        .. "doing what they are told, and you are still standing there when she puts the bucket "
                        .. "down and walks past you and up the lane. You are cold for two days afterwards in a "
                        .. "way the fire does not touch.",
                    deltas = {
                        health = -18, attr = { WIS = 1, PIE = 1 },
                        flags = { "cursed_at_the_well" },
                    },
                },
            },
            {
                label = "Take the shrine's bell and ring it at her.",
                warn = "risk",
                check = { attr = "PIE", dc = 13 },
                success = {
                    text = "You ring it from the top of the lane and the light goes out and does not come back, "
                        .. "and in the morning there is a bucket by the well with the rope still on it. The "
                        .. "shrine is pleased with you. The village is pleased with you. Nobody asks what she was "
                        .. "doing down there and you find that you would like to know.",
                    deltas = { karma = 3, attr = { PIE = 2 }, notoriety = 2, flags = { "rang_the_bell" } },
                },
                failure = {
                    text = "The bell is iron and old and the sound it makes is not the sound a holy bell makes, "
                        .. "and the light at the well turns round. You are still holding the bell when it "
                        .. "reaches you. They find you at the top of the lane in the morning and the priest will "
                        .. "not say the words over the well afterwards, which the village takes as an answer.",
                    deltas = { health = -999, flags = { "rang_the_bell" } },
                },
            },
            {
                label = "Go back to bed and let the shrine handle it.",
                warn = "safe",
                text = "You go back to bed and lie there listening, and in the morning the well is fine and the "
                    .. "woman is not at the edge of the village any more, and nobody will say which of those came "
                    .. "first. The water is sweet again by the thaw, exactly as she said it would be, and you are "
                    .. "the only person who knows that was said.",
                deltas = { attr = { WIS = 1 }, karma = -1, flags = { "left_the_well" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_INDENTURE",
        title = "The Line at the Bottom",
        stage = "adolescence",
        ageMin = 13,
        ageMax = 16,
        weight = 12,
        text = "The smith wants you for seven years and will not pay a wage, and he says so plainly, and then he "
            .. "says what the seven years are worth, which is a trade, a place at a forge, and the right to be "
            .. "called something. Your father has already said yes with his face and not out loud. There is a "
            .. "paper on the bench with a line at the bottom for a mark.",
        choices = {
            {
                label = "Make your mark.",
                warn = "safe",
                text = "You make the mark and he folds the paper and puts it in a box with other papers, and then "
                    .. "he puts a hammer in your hand that is too heavy for you and tells you to hold it properly. "
                    .. "It is the first time an adult has given you a thing and then watched to see what you would "
                    .. "do with it.",
                deltas = { exp = 120, attr = { STR = 1, VIT = 1 }, flags = { "smith_apprentice" } },
            },
            {
                label = "Ask for a wage and a shorter term.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 12 },
                success = {
                    text = "He says no to the wage and yes to the term, and then, at the door, says he will find "
                        .. "something at the quarter days. He does, and it is never much, and it is always there. "
                        .. "You have learned that the second thing a man says is the thing he can afford.",
                    deltas = { coin = 15, exp = 100, attr = { CHA = 1 }, flags = { "smith_apprentice" } },
                },
                failure = {
                    text = "He puts the paper away and says he will ask somebody else, and he does, and the "
                        .. "somebody else is a boy you have never liked. You stay in the field for another year "
                        .. "and every time you pass the forge you can hear the hammer and it is not yours.",
                    deltas = { exp = 40, coin = 4, attr = { WIS = 1 }, flags = { "smith_refused" } },
                },
            },
            {
                label = "Refuse and stay in the field.",
                warn = "safe",
                text = "You say no in front of both of them, which is the part that is remembered. The field is "
                    .. "the field and it pays a boy what a boy is worth and it does not own seven years of "
                    .. "anybody. Your father does not speak to you on the walk home and is over it by supper.",
                deltas = { coin = 12, attr = { STR = 1 }, karma = 1, flags = { "stayed_in_the_field" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_NOTCHED_STICK",
        title = "The Notched Stick",
        stage = "adolescence",
        ageMin = 14,
        ageMax = 17,
        weight = 10,
        text = "The tithe is taken in grain and the shrine's man comes with a cart and a stick, and the stick "
            .. "has notches on it for the measure, and the notches are the shrine's own. The measure has changed "
            .. "since the shrine changed hands, and the shrine has changed hands, and nobody will say to whom. "
            .. "Your father stands in the yard with the sack open and his mouth shut.",
        choices = {
            {
                label = "Pay the measure as it is.",
                warn = "safe",
                text = "You hold the sack and he takes the measure and marks it in a book, and the winter is "
                    .. "thinner for it. Your father says, afterwards, that a man who argues with a measure argues "
                    .. "with the hand that holds it, and that he has seen where that gets people.",
                deltas = { coin = -15, attr = { PIE = 1 }, karma = 1 },
            },
            {
                label = "Ask whose notches they are.",
                warn = "[INT]",
                check = { attr = "INT", dc = 11 },
                success = {
                    text = "He tells you, because it is written on the stick and he is not ashamed of it, and the "
                        .. "name is not a shrine's name and not a village's name. You tell the priest, who goes "
                        .. "quiet, and the measure is the old measure again by the next quarter, and nobody ever "
                        .. "explains why.",
                    deltas = { attr = { INT = 1, WIS = 1 }, notoriety = 2, karma = 1, flags = { "asked_the_notches" } },
                },
                failure = {
                    text = "He answers the question by asking you another one about your father's acres, and the "
                        .. "acres have never been written down anywhere, and by the time he leaves they have been "
                        .. "written down. The measure is the same measure. Something else has changed.",
                    deltas = { notoriety = 3, coin = -20, attr = { WIS = 1 } },
                },
            },
            {
                label = "Short the sack and stand in front of it.",
                warn = "risk",
                text = "You hold the sack shut with your hand on the tie and he looks at your hand for a long "
                    .. "moment and then takes the short measure and writes the full one in the book. He does it "
                    .. "for you. He will not do it twice, and now there is a page with your family's name on it "
                    .. "and a figure that is a kindness, and kindnesses are collected.",
                deltas = { coin = -5, attr = { CHA = 1 }, karma = 1, notoriety = 1, health = -5 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_MUSTER",
        title = "The Muster",
        stage = "adolescence",
        ageMin = 15,
        ageMax = 17,
        weight = 10,
        text = "The muster is on the green and every household with a body between one age and another has to "
            .. "send one, and the ages are the new lord's ages and not the old ones. You are handed a spear that "
            .. "is a spear because it has been called that for two generations. The man with the list is in a "
            .. "hurry, and the man with the spear does not look at you at all.",
        choices = {
            {
                label = "Stand in the line and learn it.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 11 },
                success = {
                    text = "You stand in the line for a season and learn to hold a spear at the right height and "
                        .. "to walk in step with people you would not otherwise speak to. It is boring and it is "
                        .. "hard and at the end of it you can do a thing that most people cannot, which nobody "
                        .. "tells you is worth anything.",
                    deltas = { attr = { STR = 1, VIT = 1 }, exp = 50, coin = 10, flags = { "mustered" } },
                },
                failure = {
                    text = "You go down in the third week with the thing that goes round the camp, and you are "
                        .. "sent home before the end of it, and the household still has to send somebody. The "
                        .. "line does not miss you. That is not a judgement, it is just what a line is.",
                    deltas = { health = -10, attr = { WIS = 1 }, coin = 5 },
                },
            },
            {
                label = "Get your name off the list.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 13 },
                success = {
                    text = "You find the man with the list at the end of the day when the list is a chore and not "
                        .. "a duty, and you give him a reason that is not quite a lie and not quite enough, and he "
                        .. "crosses the name out. He does not ask for anything. That is the frightening part, and "
                        .. "you will think about it at odd moments for years.",
                    deltas = { attr = { CHA = 1 }, karma = -1, notoriety = -1, coin = -8, flags = { "off_the_list" } },
                },
                failure = {
                    text = "He hears you out and then writes something next to your name and tells you to be on "
                        .. "the green at first light, and you are, and the something next to your name turns out "
                        .. "to mean the front. You do not find that out until much later.",
                    deltas = { coin = -8, notoriety = 2, attr = { WIS = 1 }, flags = { "mustered" } },
                },
            },
            {
                label = "Pay the fine and send nobody.",
                warn = "risk",
                text = "The fine is more than the household has and it is paid, and the green is mustered without "
                    .. "anyone from your door in it. The neighbours count. The man with the list counts. Nobody "
                    .. "says anything about it in the lane, and everybody knows, and the knowing is the cost "
                    .. "on top of the coin.",
                deltas = { coin = -20, karma = -3, notoriety = 1, flags = { "paid_the_fine" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_LETTER_READ_ALOUD",
        title = "The Letter",
        stage = "adolescence",
        ageMin = 15,
        ageMax = 17,
        weight = 9,
        text = "The letter came with a carter and cost the sender more than the paper, and it is in a hand that "
            .. "is careful and slow and has been taught late. It is addressed to the house and not to anyone in "
            .. "it, and your father holds it the way a man holds a tool he has been handed and does not know. He "
            .. "asks you to read it. There is a part near the end that you get to before you have decided "
            .. "whether to read it out.",
        choices = {
            {
                label = "Read it all.",
                warn = "[INT]",
                check = { attr = "INT", dc = 11 },
                success = {
                    text = "You read the whole of it, including the part about the money, and your father sits "
                        .. "with it for a while and then asks you to read it again, slower. The second reading is "
                        .. "for him to hear it properly. The first was for him to find out what it said without "
                        .. "anyone watching his face.",
                    deltas = { attr = { INT = 1, WIS = 1 }, karma = 2, flags = { "read_the_letter" } },
                },
                failure = {
                    text = "You stumble on the hand and lose the thread near the end, and your father says never "
                        .. "mind, and takes the letter and puts it on the shelf with the other papers that are "
                        .. "never read again. It is the only letter that will ever come from that direction.",
                    deltas = { attr = { INT = 1, CHA = -1 }, karma = -1 },
                },
            },
            {
                label = "Read it, and leave out the last part.",
                warn = "risk",
                text = "You read it up to the door of the thing and then you stop and fold it, and he does not "
                    .. "ask, and the house has a quiet winter it would not otherwise have had. You are the only "
                    .. "one who knows what the last part said, and you carry it the way you will later carry "
                    .. "several other things you decided were not for other people.",
                deltas = { karma = -3, attr = { CHA = 1 }, flags = { "trimmed_the_letter" } },
            },
            {
                label = "Say the hand is too poor to read.",
                warn = "risk",
                text = "You say it and he believes you, or he decides to, and the letter goes on the shelf with "
                    .. "the other papers. For years afterwards, when the subject comes up, he says his eldest "
                    .. "could not make out the hand, and you are in the room when he says it, and you agree.",
                deltas = { karma = -2, attr = { WIS = 1 }, flags = { "would_not_read" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_MATCH",
        title = "The Match",
        stage = "adolescence",
        ageMin = 16,
        ageMax = 17,
        weight = 10,
        text = "The family has been approached, which is how it is done, and the approach came with a number of "
            .. "animals in it and a date for the answer. You have met the person twice, both times in a room with "
            .. "other people in it, and the second time they asked you about the water in your field, which was "
            .. "either a kindness or the whole of what you will ever get. Your father has not said what he thinks "
            .. "and will not, and the animals are good.",
        choices = {
            {
                label = "Say yes.",
                warn = "safe",
                text = "You say yes in front of both houses and it is settled in an afternoon, and the animals "
                    .. "come up the lane a week later. Nobody asks whether you wanted to. You spend the following "
                    .. "years finding out whether that question was ever going to be put to anybody in this "
                    .. "village, and the answer is not comfortable.",
                deltas = { coin = 40, karma = 1, attr = { CHA = 1 }, flags = { "betrothed" } },
            },
            {
                label = "Say no.",
                warn = "risk",
                text = "You say no and the room does not know where to put it, and the animals go back down the "
                    .. "lane the same week. Your father says nothing at all, which is a speech. The person you "
                    .. "said no to marries somebody from the other side of the water and you hear about it "
                    .. "secondhand, and you are still thinking about the water question.",
                deltas = { coin = -10, karma = -1, attr = { WIS = 1 }, flags = { "refused_the_match" } },
            },
            {
                label = "Ask to meet them a third time, alone.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "It is not done, and you ask for it, and both houses decide to be broad-minded about "
                        .. "it in a way they will deny later. You walk to the water and back with them and it is "
                        .. "an hour and it is not romantic and it is the only hour of the whole arrangement that "
                        .. "belonged to either of you.",
                    deltas = { attr = { CHA = 2 }, karma = 2, flags = { "betrothed", "chose_it" } },
                },
                failure = {
                    text = "The asking is taken as an insult by the other house and as a joke by yours, and the "
                        .. "match is agreed anyway, because the animals were already good. You get your third "
                        .. "meeting. It is in the same room, with the same people in it, and it lasts less time "
                        .. "than the other two.",
                    deltas = { karma = -1, notoriety = 1, attr = { WIS = 1 }, coin = 20, flags = { "betrothed" } },
                },
            },
        },
    },

    ----------------------------------------------------------------- adulthood
    -- COMBAT LEAD 5, and the only one hard-linked to a real encounter: the same
    -- rats as ENC_GRANARY_JOB, a different granary. Tests INT on the route that
    -- avoids the fight. Loss is Defeat, as the encounter is authored — the rats
    -- want the flour, not the miller's hired hand.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_MILL_UNDERCROFT",
        title = "The Undercroft",
        stage = "adulthood",
        ageMin = 18,
        ageMax = 30,
        weight = 16,
        text = "The miller's undercroft has a floor that gives under the sacks and a smell that comes up "
            .. "through it in the afternoons. He has moved the flour to the other end and put boards over the "
            .. "soft part and told nobody, and now he wants it looked at by somebody who is not him. He pays in "
            .. "flour, and flour is worth having this year.",
        combat = {
            encounter = "ENC_GRANARY_JOB",
            severity = "defeat",
            warning = "The boards over the soft part have been walked on from underneath. Whatever is down "
                .. "there has been eating the miller's flour for a month and has got used to the arrangement.",
            stakes = "Nothing down there has any use for you dead. If it goes badly you will come up the ladder "
                .. "carried, and the miller will be more careful about what he says in the yard afterwards.",
            onWin = {
                text = "You come up into the daylight with the lamp still lit and your hands full, and the "
                    .. "miller counts the sacks with you standing there because he wants the neighbours to see "
                    .. "the counting. He pays the flour and then adds a measure to it that he does not mention, "
                    .. "which in a miller is a speech.",
                deltas = { notoriety = 3 },
            },
            onLose = {
                text = "You come to on the undercroft floor with the lamp out and the miller's voice somewhere "
                    .. "above you, going over the top of you to somebody else, about who is to carry you up and "
                    .. "what the guild rate is for a man who has to be carried. The flour you were promised is "
                    .. "not in the cart when you leave.",
                severity = "defeat",
            },
            onFlee = {
                text = "You come up the ladder fast and without the lamp, and the miller does not argue, and the "
                    .. "way he does not argue is the whole of it. He boards the hatch himself that afternoon and "
                    .. "the boards are still there when you pass the mill the following year, and the smell is "
                    .. "still coming up through them.",
            },
        },
        choices = {
            {
                label = "Go down and clear it.",
                warn = "[risk]",
                startsCombat = true,
                text = "You take the lamp down first and the hatchet after it, and the stairs are the kind that "
                    .. "were built for a man carrying a sack and not for this.",
            },
            {
                label = "Send the miller's lad down with the lamp and watch.",
                warn = "risk",
                text = "The lad is fourteen and brave in the way of somebody who has not been hurt yet, and he "
                    .. "goes down because you tell him to and because the miller is watching. What comes up the "
                    .. "ladder comes up without him. You go down after that, and you go down angry, and the "
                    .. "miller pays you and does not look at you, and the lad is not right about stairs for a "
                    .. "long time.",
                deltas = { coin = 20, karma = -4, attr = { WIS = 1 }, flags = { "sent_the_lad" } },
            },
            {
                label = "Drown them out of the race.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "You open the sluice at the low end and let the race come through the undercroft wall "
                        .. "at the one place the mortar has gone, and you watch it fill from the top of the "
                        .. "stairs. Nothing comes out. The flour nearest the floor is ruined and the miller "
                        .. "shouts about that and not about the rest, because the rest is still there.",
                    deltas = { coin = 45, exp = 45, attr = { INT = 1 }, flags = { "drowned_the_undercroft" } },
                },
                failure = {
                    text = "You open the sluice and the water does not go where the mortar has gone, it goes "
                        .. "into the flour end, and by the time you have it shut again the miller has a season's "
                        .. "worth of paste and a story about you that will be told at the mill for years.",
                    deltas = { coin = -30, karma = -1, attr = { WIS = 1 } },
                },
            },
        },
    },

    -- COMBAT LEAD 6. Enemy: the thing at the new toll bar, which has a book and
    -- does not like the light. Tests INT or DEX. Death possible on the last.
    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_TOLL_ROAD_DEAD",
        title = "The Bar on the Road",
        stage = "adulthood",
        ageMin = 22,
        ageMax = 40,
        weight = 8,
        deathText = "the toll road, and the thing at the bar that did not look up",
        text = "There is a toll bar on the road where there was no toll bar, and the thing collecting stands in "
            .. "the shadow of it because it does not like the light, and it has a book. The toll is grain, by "
            .. "weight, and the weight is taken with a scale that has been checked. Two carts ahead of you have "
            .. "paid. The third is arguing, and the argument is going badly, and the thing with the book has not "
            .. "looked up once.",
        choices = {
            {
                label = "Pay the weight and go.",
                warn = "safe",
                text = "You pay and the scale is honest and the book is written in and you are through before "
                    .. "the cart behind you has finished arguing. The road beyond the bar is better than the road "
                    .. "before it, and there is nobody on it, and the two facts are the same fact.",
                deltas = { coin = -18, attr = { WIS = 1 }, flags = { "paid_the_bar" } },
            },
            {
                label = "Ask to see the writ.",
                warn = "[INT]",
                check = { attr = "INT", dc = 13 },
                success = {
                    text = "It turns the book round without any expression at all and there is a page in the "
                        .. "front of it with a seal and a date and a schedule of weights, and the schedule does "
                        .. "not agree with the scale. It corrects the scale. It does not apologise and it does "
                        .. "not look at you, and the two carts behind you pay less than they were going to.",
                    deltas = { attr = { INT = 2 }, karma = 2, notoriety = 2, flags = { "saw_the_writ" } },
                },
                failure = {
                    text = "You ask and it looks up, and the looking up is the entire cost of the question. You "
                        .. "are on the ground before you have decided to be, and you come round on the verge with "
                        .. "your cart gone through and your grain weighed by somebody else's hand, and a man from "
                        .. "the third cart is putting a coat under your head.",
                    deltas = { health = -25, healthMaxAdjust = -4, coin = -18, attr = { WIS = 1 } },
                },
            },
            {
                label = "Turn the cart and take the old road.",
                warn = "risk",
                check = { attr = "DEX", dc = 13 },
                success = {
                    text = "You get the cart round on the narrow part, which takes doing, and the old road is "
                        .. "half a day longer and goes through a wood that nobody has cut in years. You come out "
                        .. "above the bar at dusk and nobody has written anything down. You do not use that road "
                        .. "again, because a road that works once is a road that is watched.",
                    deltas = { attr = { DEX = 1, LUK = 1 }, coin = 6, flags = { "dodged_the_bar" } },
                },
                failure = {
                    text = "The cart is too long for the turn and the wheel goes into the ditch, and while you "
                        .. "are out of the seat with your shoulder against it the shadow at the bar is no longer "
                        .. "at the bar. It does not hurry and it does not say anything and the weight it takes "
                        .. "this time is not grain.",
                    deltas = { health = -999, flags = { "took_the_old_road" } },
                },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_ASSESSMENT",
        title = "The Assessment",
        stage = "adulthood",
        ageMin = 20,
        ageMax = 45,
        weight = 12,
        text = "The assessment is done from a book, and the book was made from what the village said about "
            .. "itself, and the village lied to look poorer in a year it has since forgotten. The clerk reads the "
            .. "figure and the figure is high and the clerk is not interested in why. Behind him the road is very "
            .. "good, and the bandits are gone, and everyone in the room is doing the arithmetic on that.",
        choices = {
            {
                label = "Pay it.",
                warn = "safe",
                text = "You pay it and it is a great deal and it is taken in a way that leaves no room for a "
                    .. "second conversation. The road stays good. The bandits stay gone. You have bought a thing "
                    .. "you did not ask for, at a price that was set by somebody else, and it is a good thing.",
                deltas = { coin = -25, attr = { WIS = 1 } },
            },
            {
                label = "Take him out and show him the field.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "You walk him to the boundary and show him what the low field actually yields and "
                        .. "what the book says it yields, and he looks at both and then writes in the margin and "
                        .. "the figure comes down. He is not grateful. He is correcting an error, and he will "
                        .. "correct it again next year if somebody makes him.",
                    deltas = { coin = -10, attr = { INT = 1, WIS = 1 }, flags = { "corrected_the_book" } },
                },
                failure = {
                    text = "You show him the field and he agrees with everything you say and then explains, "
                        .. "patiently, that the book is not about your field, it is about the district, and your "
                        .. "field is a small part of a large sum. The figure goes up, because you made him look "
                        .. "at it again.",
                    deltas = { coin = -35, notoriety = 2, attr = { WIS = 1 } },
                },
            },
            {
                label = "Pay it in grain that is not grain.",
                warn = "risk",
                text = "The sacks are weighed and the weight is right and the bottom of two of them is chaff and "
                    .. "sweepings, and the clerk does not open them because the clerk does not open sacks, "
                    .. "because nobody has ever put chaff in one before. It works. It works for two years, and "
                    .. "then somebody opens a sack, and the somebody has a book and a great deal of patience.",
                deltas = { coin = 10, karma = -3, notoriety = 3, attr = { LUK = 1 }, flags = { "shorted_the_levy" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_WELL_GOES_SOUR",
        title = "The Well Goes Sour",
        stage = "adulthood",
        ageMin = 22,
        ageMax = 50,
        weight = 12,
        text = "The well has gone sour in the way wells do, and the spring that fed it is somewhere under ground "
            .. "that has been doing things it did not used to do. The next water is at the shrine, and the shrine "
            .. "has started charging, and it has started charging in a way that has a figure and no argument. "
            .. "Two households are already carrying from it, and one of them has stopped speaking to the other.",
        choices = {
            {
                label = "Carry from the shrine and pay.",
                warn = "safe",
                text = "You carry it and pay for it and the carrying is the worse half, and the shrine's water is "
                    .. "cold and clean and the queue at it is the only place in the village where everybody has "
                    .. "to stand next to everybody. You hear more in a season at that queue than you have heard "
                    .. "in ten years in the lane.",
                deltas = { coin = -12, attr = { VIT = 1 }, health = -3, flags = { "carries_from_the_shrine" } },
            },
            {
                label = "Dig where the old man says the spring runs.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "The old man has not been right about anything for years and he is right about this, "
                        .. "and the water comes up grey and then clear, and by the autumn half the lane is "
                        .. "drawing from a hole in your own ground. You do not charge for it. You do not let "
                        .. "anybody forget who dug it, either.",
                    deltas = {
                        coin = -6, attr = { INT = 1, STR = 1 }, karma = 2,
                        notoriety = 1, flags = { "dug_the_well" },
                    },
                },
                failure = {
                    text = "You dig for eleven days and find clay, and the clay is good for nothing, and the "
                        .. "hole fills with rainwater and stands there green all summer. The lane calls it your "
                        .. "well, which it is not, and it is the sort of name that stays.",
                    deltas = { health = -8, coin = -6, attr = { WIS = 1 } },
                },
            },
            {
                label = "Draw from the mill race and say nothing.",
                warn = "risk",
                text = "It is the same water that has been going through the mill for a hundred years and it is "
                    .. "only the village's pride that ever called it unfit. Two of the household are ill within "
                    .. "the fortnight and one of them stays ill, and you keep drawing from it, because the shrine "
                    .. "water is coin and the coin is not there.",
                deltas = { health = -12, karma = -2, attr = { DEX = 1 }, flags = { "drank_the_race" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_A_NAME_ON_A_LIST",
        title = "A Name on a List",
        stage = "adulthood",
        ageMin = 20,
        ageMax = 35,
        weight = 10,
        text = "Your brother went into the levy in the spring and the levy has been somewhere since, and the "
            .. "only news that comes back comes back as a list read out at the shrine. The list this month is "
            .. "shorter than the list last month, and the names on it are read in the order they were written "
            .. "down. The priest reads quickly now, which he did not used to do.",
        choices = {
            {
                label = "Go to the shrine and ask to see the list yourself.",
                warn = "[INT]",
                check = { attr = "INT", dc = 11 },
                success = {
                    text = "The list is in two columns and the second column is a place and the place is not a "
                        .. "place anybody in the village has heard of. Your brother's name is in the first "
                        .. "column. You read it twice to be sure, and then you go home and say nothing, and for a "
                        .. "year you know something the house does not.",
                    deltas = { attr = { INT = 1, WIS = 2 }, karma = 1, flags = { "saw_the_list" } },
                },
                failure = {
                    text = "The priest will not have it out of the box with you in the room, and the refusal is "
                        .. "polite and complete, and you go home having learned only that the list is kept in a "
                        .. "box. That night you do not sleep, and the not sleeping costs you a week.",
                    deltas = { attr = { WIS = 1 }, health = -5, flags = { "saw_the_list" } },
                },
            },
            {
                label = "Wait for the next list, like everybody else.",
                warn = "safe",
                text = "You wait, and the next list comes, and his name is not on it, and no one reads out the "
                    .. "names that are not on it. Your mother takes the not-being-on-it as good news for the rest "
                    .. "of her life, and you let her, and you both know which of you is doing the letting.",
                deltas = { attr = { WIS = 1 }, karma = -1, flags = { "waited_for_the_list" } },
            },
            {
                label = "Buy his way out with what you have.",
                warn = "risk",
                text = "There is a man in the district town who does this and he is not hard to find and he is "
                    .. "very calm. The coin goes, and the discharge comes, and your brother comes home in the "
                    .. "autumn, and he is not the same and he does not say why, and the household's money is "
                    .. "gone for a generation.",
                deltas = { coin = -40, karma = 2, notoriety = 1, attr = { WIS = 1 }, flags = { "bought_him_out" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_BARN_AND_THE_TWO_RICKS",
        title = "The Barn and the Two Ricks",
        stage = "adulthood",
        ageMin = 25,
        ageMax = 50,
        weight = 10,
        text = "The barn went up in the dry month with the door shut, which is not how a barn burns by itself. "
            .. "By the time the buckets came it was the barn and the two ricks and the fence, and the family that "
            .. "had it is standing in the lane with nothing that is not on their backs. Somebody did it. Half the "
            .. "lane has decided who, and the half that has decided is the half that always decides.",
        choices = {
            {
                label = "Say the name the lane has decided on.",
                warn = "risk",
                text = "You say it in the yard where the saying carries, and it is not your name and it is not "
                    .. "your accusation, exactly, and the man it lands on is gone from the village inside a "
                    .. "season. Nothing is proved. Nothing is ever proved, and the lane is satisfied, and you have "
                    .. "found out what you are willing to do when a room wants a name.",
                deltas = { karma = -5, notoriety = 3, attr = { CHA = 1 }, flags = { "named_the_name" } },
            },
            {
                label = "Say you saw nothing, because you saw nothing.",
                warn = "safe",
                text = "You say it and it is true and it does not help, and the lane takes your saying-nothing "
                    .. "as a kind of cowardice and the family takes it as a kind of sense. The man the lane "
                    .. "decided on stays in the village and is careful with his fires for the rest of his life.",
                deltas = { karma = 1, attr = { WIS = 1 }, notoriety = -1 },
            },
            {
                label = "Give the family your own rick.",
                warn = "safe",
                text = "You have the rick carted over in the afternoon before anyone has finished being shocked, "
                    .. "which means it cannot be refused. They take it. It is the whole of what the winter was "
                    .. "going to be. Somebody in the lane says something about you that is not a compliment and "
                    .. "you find that it does not matter to you at all.",
                deltas = { coin = -20, karma = 5, attr = { PIE = 1 }, flags = { "gave_the_rick" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_GROUND_ACROSS_THE_WATER",
        title = "The Ground Across the Water",
        stage = "adulthood",
        ageMin = 25,
        ageMax = 45,
        weight = 10,
        text = "The woman across the water lost her man in the fighting and the ground he worked is now ground "
            .. "nobody works, and it lies between your field and the road, and it is going to grass. She has not "
            .. "asked you for anything. She has started leaving her gate open in a way that is either an "
            .. "invitation or the beginning of not caring, and you have been walking past it for a season.",
        choices = {
            {
                label = "Work it and split it with her.",
                warn = "[CHA]",
                check = { attr = "CHA", dc = 11 },
                success = {
                    text = "You put the offer plainly and she takes a day to think about it, which you respect, "
                        .. "and then she takes half, which is more than you offered and less than the ground is "
                        .. "worth. It works for years. Neither of you ever calls it anything, and the gate stays "
                        .. "open, and the lane has an opinion it keeps to itself.",
                    deltas = { coin = 20, karma = 4, attr = { CHA = 1 }, flags = { "worked_her_ground" } },
                },
                failure = {
                    text = "You put the offer badly, and it comes out as a kindness when it is a piece of "
                        .. "business, and she hears it that way and takes it anyway because the ground is going "
                        .. "to grass. You work it all season and it is not the same as before, and the lane "
                        .. "watches the whole arrangement with interest.",
                    deltas = { coin = 8, karma = 2, attr = { WIS = 1 }, notoriety = 1 },
                },
            },
            {
                label = "Offer to buy it.",
                warn = "risk",
                text = "She sells, and the price is fair, and it is done at the shrine with the priest writing, "
                    .. "and afterwards she goes to live with her sister across the water and does not come back. "
                    .. "The ground is good. You made a fair offer to a woman with no other offer, which is a "
                    .. "sentence that will sit in you for a while.",
                deltas = { coin = -30, karma = -2, attr = { WIS = 1 }, flags = { "bought_her_ground" } },
            },
            {
                label = "Keep walking past.",
                warn = "safe",
                text = "You walk past it every day for a season and then the grass is knee-high and then it is "
                    .. "not a field any more, it is a piece of ground that used to be one. She stays. Somebody "
                    .. "else's son works it eventually. You never say a word about it and you never once stop "
                    .. "noticing it.",
                deltas = { attr = { WIS = 1 }, karma = -1 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_HOT_CHILD",
        title = "The Hot Child",
        stage = "adulthood",
        ageMin = 28,
        ageMax = 45,
        weight = 10,
        text = "The child has been hot since market day and the hot is not going down, and the woman who knows "
            .. "about fevers is on the other side of the water, and the shrine has a priest who will come for a "
            .. "coin, and the coin is in the box. Your own mother did this with you and you do not remember any "
            .. "of it, which means she did it well or it did not happen.",
        choices = {
            {
                label = "Pay the priest to come.",
                warn = "safe",
                text = "He comes and says the words and puts a hand on the child's head and stays until the "
                    .. "morning, and the child is cooler by dawn. Whether that is the words or the night or the "
                    .. "child's own blood is a thing you will never know, and you find, standing in the doorway, "
                    .. "that you have stopped caring which.",
                deltas = { coin = -20, karma = 2, attr = { PIE = 1 }, flags = { "the_child_lived" } },
            },
            {
                label = "Fetch the woman who knows about fevers.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 11 },
                success = {
                    text = "She comes at night in a boat and she is not what the shrine says she is, and she "
                        .. "brings a draught that smells of a burnt field and sits with the child until it is "
                        .. "light. She takes her coin and says what to watch for and leaves before the lane is up, "
                        .. "and you do exactly what she said for three days.",
                    deltas = { coin = -10, karma = 1, attr = { WIS = 2 }, flags = { "the_child_lived" } },
                },
                failure = {
                    text = "She comes too late or the draught is the wrong one or the child was already past it, "
                        .. "and none of those is the same thing and you will spend years deciding which it was. "
                        .. "The shrine will not say the words over the grave of a child who was given a witch's "
                        .. "draught, so you say them yourself, badly, and the lane stands there and lets you.",
                    deltas = { coin = -10, karma = -1, attr = { WIS = 1, PIE = -1 }, flags = { "the_child_buried" } },
                },
            },
            {
                label = "Sit up with it and do what your mother did.",
                warn = "[VIT]",
                check = { attr = "VIT", dc = 12 },
                success = {
                    text = "You sit up for four nights with a bowl and a cloth and you do not sleep and you do "
                        .. "not leave the room, and on the fifth morning the child asks for water and is annoyed "
                        .. "about something, and you go out into the yard and stand there for a while in the "
                        .. "cold, shaking.",
                    deltas = { health = -6, attr = { VIT = 1, WIS = 1 }, karma = 2, flags = { "the_child_lived" } },
                },
                failure = {
                    text = "You sit up for four nights and it is not enough, and the thing you will remember is "
                        .. "not the last night, it is the fourth afternoon, when the child was lucid for an hour "
                        .. "and asked you something ordinary and you answered it.",
                    deltas = { health = -8, karma = 1, attr = { WIS = 1 }, flags = { "the_child_buried" } },
                },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_ROLL_OF_THE_HOUSEHOLD",
        title = "The Roll of the Household",
        stage = "adulthood",
        ageMin = 30,
        ageMax = 50,
        weight = 10,
        text = "A clerk has come to write down every person in the house, with their age, their trade, and what "
            .. "they can lift, and the form has a column for a thing it calls a levy and another for a thing it "
            .. "does not explain. He is polite and he is fast and he has done a great many houses. He asks "
            .. "whether anyone in the house has ever held a weapon, and then he waits, and he does not write "
            .. "until you answer.",
        choices = {
            {
                label = "Answer everything.",
                warn = "safe",
                text = "You answer all of it, including the weapon, which was a spear at a muster and a "
                    .. "grandfather's bow that has not been strung in living memory. He writes both down. Nothing "
                    .. "happens for two years, and then a form comes about the bow, and the form has a box on it "
                    .. "for where the bow is.",
                deltas = { coin = 5, attr = { WIS = 1 }, notoriety = 1, flags = { "on_the_roll" } },
            },
            {
                label = "Leave out the oldest.",
                warn = "risk",
                text = "You say the house has four in it and it has five, and he writes four, and the oldest is "
                    .. "invisible on paper for as long as the paper lasts. It is not much of a lie and it is the "
                    .. "first one you have told an office rather than a person, and you find the distinction "
                    .. "matters to you more than the lie does.",
                deltas = { karma = 1, attr = { CHA = 1 }, notoriety = -1, flags = { "trimmed_the_roll" } },
            },
            {
                label = "Ask what the second column is for.",
                warn = "[INT]",
                check = { attr = "INT", dc = 12 },
                success = {
                    text = "He tells you, because it is not a secret and it is only a secret in a village where "
                        .. "nobody has ever asked. It is a list of people who can be moved, and it is being made "
                        .. "in every district at once, and he says that last part the way a man says the weather. "
                        .. "You do not sleep well that night and you are right not to.",
                    deltas = { attr = { INT = 2, WIS = 1 }, notoriety = 2, flags = { "knows_the_column" } },
                },
                failure = {
                    text = "He answers by writing something in the margin next to your name and closing the book, "
                        .. "and after that he is polite in a different way, and the different way is the one that "
                        .. "gets people written to about.",
                    deltas = { notoriety = 4, attr = { WIS = 1 }, flags = { "asked_the_column" } },
                },
            },
        },
    },

    -- Chain continuation of E_GOAT_ARGUMENT. Reached by `next`, never drawn.
    -- TIER: authored (Events.All), chainOnly.
    {
        id = "E_THE_GOAT_THAT_WAS_OWED",
        title = "The Kid on the Rope",
        stage = "adulthood",
        ageMin = 38,
        ageMax = 55,
        weight = 10,
        chainOnly = true,
        requires = { flags = { "hedge_conceded" } },
        text = "The neighbour is old and the argument is old and the goat is long dead, and this morning he has "
            .. "come up the lane with a kid on a rope and no explanation. He says the hedge grew back and the "
            .. "ground was never his and the kid is what a man owes for a thing he was right about for too long. "
            .. "He does not come into the yard.",
        choices = {
            {
                label = "Take the kid.",
                warn = "safe",
                text = "You take the rope and he nods and goes back down the lane, and neither of you says "
                    .. "anything that would have to be remembered. The kid is worth something. It is not worth "
                    .. "what he has decided it is worth, and that is the point of it, and you both know that.",
                deltas = { coin = 12, karma = 2, attr = { WIS = 1 }, flags = { "settled_the_hedge" } },
            },
            {
                label = "Take the kid and send something back.",
                warn = "safe",
                text = "You take it and that evening you send a measure of the good grain down the lane with one "
                    .. "of the children, and the measure is refused and sent back, and you send it again the "
                    .. "following week and it is not refused the second time. That is the whole of the treaty.",
                deltas = { coin = -6, karma = 4, attr = { CHA = 1 }, flags = { "settled_the_hedge" } },
            },
            {
                label = "Tell him to keep it and forget the hedge.",
                warn = "risk",
                text = "You tell him the hedge is a hedge and the ground is ground and he should keep his kid, "
                    .. "and he stands there in the lane holding the rope, and then he says something short and "
                    .. "goes. He is dead within the year. The kid is in his daughter's yard and the daughter does "
                    .. "not know why it is not yours.",
                deltas = { karma = 3, attr = { WIS = 2 }, notoriety = -1 },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_SERGEANT_AT_THE_DOOR",
        title = "The Sergeant at the Door",
        stage = "adulthood",
        ageMin = 30,
        ageMax = 52,
        weight = 9,
        text = "The man at the door has a sergeant's coat and no sergeant's authority, and you knew him when he "
            .. "had neither, and he has come a long way to a house he remembered. He wants a night and a horse. "
            .. "He does not say what he is running from and he is not going to. There is a light on the road "
            .. "behind him, a long way off, and it is moving at a walk.",
        choices = {
            {
                label = "Take him in.",
                warn = "risk",
                text = "He sleeps in the byre and is gone before the light is up, and he takes the horse and "
                    .. "leaves the coat on the peg, and the coat is the reason there are men in the yard the "
                    .. "following afternoon asking questions in a tired voice. You have a coat now. You have not "
                    .. "decided what to do with it and you have had a year to decide.",
                deltas = { karma = 3, notoriety = 3, coin = -10, attr = { WIS = 1 }, flags = { "sheltered_him" } },
            },
            {
                label = "Give him the horse and shut the door.",
                warn = "safe",
                text = "You put the halter in his hand in the dark and shut the door on him, and he does not say "
                    .. "thank you and does not say anything else. In the morning the horse is gone and the light "
                    .. "on the road has gone past your lane without turning up it, and you never find out which of "
                    .. "those two facts is the reason for the other.",
                deltas = { coin = -15, karma = 1, attr = { WIS = 1 }, flags = { "gave_the_horse" } },
            },
            {
                label = "Send him on, and tell the light.",
                warn = "risk",
                text = "You send him up the lane and then you walk out to the road and stand where you can be "
                    .. "seen, and the light comes to you and stops, and a voice asks you a question you can "
                    .. "answer in one word. You answer it. The light goes up the lane at a walk and you go back "
                    .. "inside and shut the door and are, on paper, a good and helpful household.",
                deltas = { karma = -5, coin = 15, notoriety = 1, attr = { WIS = 1 }, flags = { "told_the_light" } },
            },
        },
    },

    -- TIER: authored (Events.All). Fires once.
    {
        id = "E_THE_SECOND_TOMB",
        title = "The Second One",
        stage = "adulthood",
        ageMin = 44,
        ageMax = 55,
        weight = 8,
        text = "There is a second one. It is smaller than the first and further out, and the plain around it has "
            .. "started to be wrong in the same way, and the grass on one side of it is a fortnight ahead of the "
            .. "grass on the other. The district sent a man to look at it and the man did not come back and the "
            .. "district has stopped asking. The almanac is still being printed with the old weather in it and "
            .. "the old weather has stopped arriving.",
        choices = {
            {
                label = "Move the household west.",
                warn = "risk",
                text = "You sell what can be sold and give away what cannot and you go west with a cart and a "
                    .. "family and a road that has no toll bar on it yet. The land you take is worse and the "
                    .. "people are strangers and the weather there is the weather that used to be here, which is "
                    .. "either luck or a schedule.",
                deltas = { coin = -30, karma = 2, attr = { WIS = 1 }, flags = { "moved_west" } },
            },
            {
                label = "Stay, and put the store deeper.",
                warn = "safe",
                text = "You dig the store out under the floor of the byre and line it with stone and fill it, and "
                    .. "it takes a season, and the season is the last one in which digging is a normal thing to "
                    .. "be doing. You are as ready as a person can be. It does not feel like readiness, it feels "
                    .. "like a hole in the ground.",
                deltas = { coin = -15, attr = { WIS = 1, STR = 1 }, health = -4, flags = { "dug_the_store" } },
            },
            {
                label = "Go and look at it yourself.",
                warn = "[WIS]",
                check = { attr = "WIS", dc = 13 },
                success = {
                    text = "You go out on the plain in the early morning and you stop a long way off and you "
                        .. "look at it for an hour without going any closer, which is the whole of the skill. What "
                        .. "you learn is that the grass is not ahead, the grass is the same, and it is the ground "
                        .. "that is a fortnight behind. You come home and you say so, and nobody wants to hear it.",
                    deltas = { attr = { WIS = 2, PIE = 1 }, flags = { "looked_at_the_second" } },
                },
                failure = {
                    text = "You go closer than you meant to and you lose an afternoon, and you come back with a "
                        .. "headache that lasts a month and a certainty that you were out there for less time than "
                        .. "the sun says you were. Nobody in the house believes the second part, and you stop "
                        .. "saying it, and you do not go out on the plain again.",
                    deltas = {
                        health = -25, healthMaxAdjust = -5, attr = { WIS = 1, PIE = 1 },
                        flags = { "looked_at_the_second" },
                    },
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
