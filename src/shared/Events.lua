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
            repeatable= false,
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
}

-- ===========================================================================
-- Eligibility and draw
-- ===========================================================================

--- Look up a stat by key: an attribute, or one of the tracked resources.
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
    if event.ageMin and event.ageMax and event.ageMax > event.ageMin then
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

--- The pool this character can currently draw from, minus anything fired.
--- `chainOnly` events are never in the pool: they only fire from a chain.
function Events.pool(state)
    local pool = {}
    for _, event in ipairs(Events.All) do
        local fired = state.fired[event.id]
        if not event.chainOnly and not (fired and not event.repeatable) then
            if Events.isEligible(event, state) then
                table.insert(pool, event)
            end
        end
    end
    return pool
end

function Events.byId(id)
    for _, event in ipairs(Events.All) do
        if event.id == id then
            return event
        end
    end
    return nil
end

--- Weighted draw. Returns nil when the pool is empty (a quiet year).
function Events.draw(state, rng)
    local pool = Events.pool(state)
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
