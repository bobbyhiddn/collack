-- Presentation-only procedural cue bank. Every sample is synthesized from the
-- committed art tokens; no downloaded or bundled recording is used.

local M = {}

local TAU = math.pi * 2
local MINSTD_MODULUS = 2147483647
local MINSTD_MULTIPLIER = 48271

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function oscillator(kind, phase, random)
    if kind == "triangle" then
        return (2 / math.pi) * math.asin(math.sin(phase))
    elseif kind == "noise" then
        return random() * 2 - 1
    end
    return math.sin(phase)
end

local function synthesize(recipe, audio)
    local sample_count = math.max(1, math.floor(recipe.duration * audio.sample_rate + 0.5))
    local sound_data = love.sound.newSoundData(
        sample_count,
        audio.sample_rate,
        audio.bit_depth,
        audio.channels
    )
    local phases = {}
    for index = 1, #recipe.voices do phases[index] = 0 end
    local seed = recipe.seed or 1
    local function random()
        seed = (seed * MINSTD_MULTIPLIER) % MINSTD_MODULUS
        return seed / MINSTD_MODULUS
    end
    for sample = 0, sample_count - 1 do
        local time = sample / audio.sample_rate
        local progress = sample_count > 1 and sample / (sample_count - 1) or 1
        local attack = recipe.attack > 0 and math.min(1, time / recipe.attack) or 1
        local remaining = recipe.release > 0
            and math.min(1, (recipe.duration - time) / recipe.release)
            or 1
        local envelope = attack * remaining * remaining
        local mixed = 0
        for index, voice in ipairs(recipe.voices) do
            local frequency = voice.from + (voice.to - voice.from) * progress
            phases[index] = phases[index] + TAU * frequency / audio.sample_rate
            mixed = mixed + oscillator(voice.wave, phases[index], random) * voice.gain
        end
        sound_data:setSample(sample, clamp(mixed * envelope * audio.master_gain, -0.92, 0.92))
    end
    return sound_data
end

function M.new(audio_tokens)
    local bank = {
        tokens = audio_tokens,
        cues = {},
        clock = 0,
        unlocked = false,
        muted = false,
    }
    for name, recipe in pairs(audio_tokens.cues) do
        local data = synthesize(recipe, audio_tokens)
        local cue = { pool = {}, cursor = 1, last_played = -1000 }
        for index = 1, 3 do
            cue.pool[index] = love.audio.newSource(data, "static")
        end
        bank.cues[name] = cue
    end
    return bank
end

function M.update(bank, dt)
    bank.clock = bank.clock + math.max(0, tonumber(dt) or 0)
end

function M.unlock(bank)
    bank.unlocked = true
    love.audio.setVolume(bank.muted and 0 or 1)
end

function M.set_muted(bank, muted)
    bank.muted = muted == true
    love.audio.setVolume(bank.muted and 0 or 1)
end

function M.play(bank, name, pitch)
    local cue = bank.cues[name]
    if not cue or not bank.unlocked or bank.muted then return false end
    if bank.clock - cue.last_played < bank.tokens.cue_cooldown then return false end
    cue.last_played = bank.clock
    local source = cue.pool[cue.cursor]
    cue.cursor = cue.cursor % #cue.pool + 1
    source:stop()
    source:setPitch(pitch or 1)
    source:play()
    return true
end

return M
