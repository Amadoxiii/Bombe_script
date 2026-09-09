-- Règles exclusivement ludiques. Seuls les indices publics sont répliqués.
BombPuzzle = {}
local P = BombPuzzle
local typeDigit = { explosive = 1, bio = 2, nuke = 3, emp = 4 }
local colors = { 'red', 'blue', 'green', 'yellow', 'white' }
local busIndex = { A = 0, B = 1, C = 2 }

function P.Derive(kind, clues)
    local digits = assert(clues.serial:match('^[A-Z][A-Z]%-(%d%d%d%d)$'), 'Invalid serial')
    local last = tonumber(digits:sub(-1))
    return {
        wire = colors[last % 5 + 1],
        switches = { ['1'] = last % 2 == 0, ['2'] = clues.cells >= 3 },
        knobs = { ['1'] = last * 30, ['2'] = clues.cells * 45 + busIndex[clues.bus] * 15 },
        pin = digits:reverse() .. typeDigit[kind] .. clues.cells
    }
end

function P.Generate(kind, random)
    random = random or math.random
    local clues = {
        version = 1,
        serial = ('%s%s-%04d'):format(string.char(random(65,90)), string.char(random(65,90)), random(0,9999)),
        cells = random(1,4),
        bus = string.char(random(65,67))
    }
    local initial = { switches = {}, knobs = {} }
    for _, id in ipairs(Config.SwitchIds) do initial.switches[id] = random(0,1) == 1 end
    for _, id in ipairs(Config.KnobIds) do initial.knobs[id] = random(0,23) * 15 end
    return clues, P.Derive(kind, clues), initial
end

