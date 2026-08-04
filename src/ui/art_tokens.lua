-- Callack vertical-slice art/audio/UX tokens, contract version 1.
--
-- This module is intentionally data-only and Lua 5.1 compatible. It can be
-- required by the LÖVE client without a JSON parser or an asset loader. All
-- colours are authored here; no external visual or audio asset is implied.

local rule_ast = require("battle.rule_ast")

local function rgb(hex)
    assert(type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$"),
        "art token colours must use #RRGGBB")
    return {
        tonumber(hex:sub(2, 3), 16) / 255,
        tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255,
    }
end

local function colour(hex)
    return { hex = hex, rgb = rgb(hex) }
end

local M = {
    version = 1,
    logical_surface = {
        phone = { width = 390, height = 844 },
        desktop = { width = 1280, height = 800 },
        desktop_min = { width = 1024, height = 720 },
        desktop_max_content_width = 1440,
    },
    spacing = { 4, 8, 12, 16, 24, 32 },
    radius = {
        chip = 4,
        control = 8,
        card = 12,
        panel = 16,
        marble = 999,
    },
    stroke = {
        hairline = 1,
        control = 2,
        selected = 3,
        focus = 3,
    },
    touch = {
        minimum = 48,
        primary_height = 56,
        icon_visual = 24,
        drag_handle = 32,
        edge_guard = 12,
    },
}

M.palette = {
    shadow = colour("#0C0907"),
    ink = colour("#17130F"),
    walnut_900 = colour("#241A14"),
    walnut_700 = colour("#4A3022"),
    walnut_500 = colour("#75492E"),
    felt_900 = colour("#18271F"),
    felt_700 = colour("#294238"),
    felt_500 = colour("#3A5B4D"),
    paper_100 = colour("#F5E8CF"),
    paper_300 = colour("#DAC8A7"),
    paper_ink = colour("#2A211A"),
    chalk = colour("#FFF4DE"),
    muted = colour("#CBB995"),
    brass_600 = colour("#B88636"),
    brass_ink = colour("#6D4B17"),
    brass_300 = colour("#E3C06B"),
    brass_100 = colour("#F7E3A2"),
    damage = colour("#DF684F"),
    restore = colour("#7EAD74"),
    focus = colour("#FFD36A"),
    player_a = colour("#E09A45"),
    player_b = colour("#63B8A6"),
    rarity_common = colour("#B7AA92"),
    rarity_uncommon = colour("#71A66E"),
    rarity_rare = colour("#5794BF"),
    rarity_epic = colour("#9A73B5"),
    rarity_legendary = colour("#E1A547"),
    family_basic = colour("#8D7F68"),
    family_defensive = colour("#5E8E86"),
    family_effect = colour("#8C6C9B"),
    family_utility = colour("#B07142"),
    family_rare = colour("#C09A4A"),
    status_poison = colour("#8AAE5A"),
    status_freeze = colour("#8DBFC8"),
    effect_magnetic = colour("#C1A05A"),
    effect_shatter = colour("#D98A73"),
}

M.material = {
    mineral = {
        jade = { base = colour("#5F9F78"), pattern = "lattice" },
        obsidian = { base = colour("#342C3C"), pattern = "shard" },
        quartz = { base = colour("#D8D0B8"), pattern = "banded" },
        flint = { base = colour("#987564"), pattern = "spiral" },
        silver = { base = colour("#AAB5B2"), pattern = "veined" },
        granite = { base = colour("#756F68"), pattern = "mottled" },
        chalk = { base = colour("#E8DDBF"), pattern = "plain" },
    },
    glass = {
        edge_alpha = 0.92,
        body_alpha = 0.78,
        inner_alpha = 0.42,
        highlight_alpha = 0.62,
        shadow_alpha = 0.34,
        rim_width = 2,
        highlight_offset_x = -0.24,
        highlight_offset_y = -0.28,
    },
    felt = {
        tile = 128,
        seed = 9125,
        fibre_count = 72,
        fibre_alpha = 0.055,
        fibre_length_min = 2,
        fibre_length_max = 6,
    },
    brick = {
        bevel = 3,
        chip_count_min = 2,
        chip_count_max = 5,
        grain_alpha = 0.10,
    },
    wood = {
        grain_lines = 5,
        grain_alpha = 0.14,
    },
}

M.type_scale = {
    micro = 11,
    meta = 12,
    label = 13,
    body = 16,
    card_title = 18,
    section = 20,
    display = 28,
    result = 36,
    line_height = 1.22,
}

local rarity_visual = {
    common = { colour = "rarity_common", rim_width = 1, shoulder_notches = 0 },
    uncommon = { colour = "rarity_uncommon", rim_width = 2, shoulder_notches = 1 },
    rare = { colour = "rarity_rare", rim_width = 2, shoulder_notches = 2 },
    epic = { colour = "rarity_epic", rim_width = 3, shoulder_notches = 3 },
    legendary = { colour = "rarity_legendary", rim_width = 3, shoulder_notches = 4 },
}
local function rarity_token(rarity)
    local tier = rule_ast.tier(rarity)
    if not tier then return nil end
    local visual = rarity_visual[rarity]
    return {
        rank = tier.rank,
        colour = visual.colour,
        shell_cap = tier.shell_cap,
        beads = tier.rank,
        rim_width = visual.rim_width,
        shoulder_notches = visual.shoulder_notches,
    }
end

function M.rarity_token(rarity)
    return rarity_token(rarity)
end

M.behaviour = {
    inert = {
        family = "basic", label = "BASE", sigil = "centre_dot",
    },
    absorb = {
        family = "defensive", label = "BODY", sigil = "inward_brackets",
    },
    reflect = {
        family = "defensive", label = "REF", sigil = "opposed_chevrons",
    },
    regenerate = {
        family = "defensive", label = "REG", sigil = "broken_ring_leaf",
    },
    fortify = {
        family = "defensive", label = "FORT", sigil = "three_block_wall",
    },
    poison = {
        family = "effect", label = "PSN", sigil = "droplet_dot",
    },
    freeze = {
        family = "effect", label = "FRZ", sigil = "six_spoke_flake",
    },
    magnetic = {
        family = "effect", label = "MAG", sigil = "horseshoe",
    },
    shatter = {
        family = "effect", label = "SHT", sigil = "broken_diamond",
    },
    chain = {
        family = "utility", label = "CHAIN", sigil = "linked_ovals",
    },
    vault = {
        family = "utility", label = "VLT", sigil = "stone_arch",
    },
    splice = {
        family = "utility", label = "GUARD", sigil = "branch_y",
    },
    dummy = {
        family = "utility", label = "DMY", sigil = "crosshair_x",
    },
    aegis = {
        family = "rare", label = "AEG", sigil = "pointed_shield",
    },
    void = {
        family = "rare", label = "VOID", sigil = "hollow_disc",
    },
    mirror = {
        family = "rare", label = "MIR", sigil = "split_vertical",
    },
    temporal = {
        family = "rare", label = "TMP", sigil = "hourglass",
    },
}

M.collision = {
    chip = { label = "CHIP", mark = "one_wedge" },
    cleave = { label = "CLEAVE", mark = "double_slash" },
    splinter = { label = "SPLINTER", mark = "forked_line" },
    ward = { label = "WARD", mark = "ring_bar" },
    heavy = { label = "HEAVY", mark = "filled_hammer" },
}

M.release = {
    baseline = { label = "BLOWBACK", mark = "outward_ring" },
    shrapnel = { label = "SHRAPNEL", mark = "four_shards" },
    concussion = { label = "CONCUSSION", mark = "double_ring" },
    magnetize = { label = "MAGNETIZE", mark = "inward_ring" },
    scorch = { label = "SCORCH", mark = "three_flame" },
}

M.status = {
    poison = {
        label = "POISON", colour = "status_poison",
        mark = "two_bubbles", anchor = "lower_left",
    },
    freeze = {
        label = "FREEZE", colour = "status_freeze",
        mark = "three_edge_ticks", anchor = "upper_right",
    },
}

-- A compact mark and canonical verb label shared by card inspection and live
-- battle attribution. These tokens carry identity only; rule meaning remains
-- in battle/rule_ast.lua.
M.rule_operation = {
    accelerate = { label = "ACCELERATE", mark = "ACC" },
    aim = { label = "AIM", mark = "AIM" },
    amplify = { label = "AMPLIFY", mark = "AMP" },
    apply_status = { label = "APPLY STATUS", mark = "STS" },
    ["break"] = { label = "BREAK", mark = "BRK" },
    cover = { label = "COVER", mark = "COV" },
    deal = { label = "DEAL", mark = "DMG" },
    heal = { label = "RESTORE", mark = "RST" },
    hold = { label = "HOLD", mark = "HLD" },
    launch = { label = "LAUNCH", mark = "LCH" },
    negate = { label = "NEGATE", mark = "NEG" },
    persist = { label = "PERSIST", mark = "DUR" },
    pierce = { label = "PIERCE", mark = "PRC" },
    prevent = { label = "PREVENT", mark = "PRV" },
    protect = { label = "PROTECT", mark = "GRD" },
    pull = { label = "PULL", mark = "PUL" },
    push = { label = "PUSH", mark = "PSH" },
    rebound = { label = "REBOUND", mark = "RBD" },
    redirect = { label = "REDIRECT", mark = "DIR" },
    rewind = { label = "REWIND", mark = "RWD" },
    scatter = { label = "SCATTER", mark = "SCT" },
    scorch = { label = "SCORCH", mark = "FIR" },
    set = { label = "SET", mark = "SET" },
    slow = { label = "SLOW", mark = "SLW" },
    splash = { label = "SPLASH", mark = "SPL" },
    target = { label = "TARGET", mark = "TGT" },
    wear = { label = "WEAR", mark = "WER" },
}

M.sling = {
    training_sling = { label = "TRAINING", hardware = "plain_pins" },
    tuned_sling = { label = "TUNED", hardware = "calibration_screw" },
    heavy_sling = { label = "HEAVY", hardware = "weighted_plate" },
    raker_sling = { label = "RAKER", hardware = "angled_tooth" },
    volley = { label = "VOLLEY", hardware = "twin_pins" },
    momentum = { label = "MOMENTUM", hardware = "weighted_lower_plate" },
    ricochet = { label = "RICOCHET", hardware = "angled_brass_shoe" },
    spread = { label = "SPREAD", hardware = "forked_band_guide" },
    precision = { label = "PRECISION", hardware = "sight_ring" },
    effect_amplifier = { label = "EFFECT AMPLIFIER", hardware = "mineral_inset" },
}

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

M.layout = {
    phone = {
        draft = {
            chrome = rect(12, 12, 366, 52),
            phase = rect(16, 72, 358, 28),
            offers = {
                rect(16, 108, 358, 148),
                rect(16, 264, 358, 148),
                rect(16, 420, 358, 148),
            },
            loadout = rect(16, 584, 358, 112),
            detail_hint = rect(16, 708, 358, 44),
            primary = rect(16, 772, 358, 56),
        },
        formation = {
            chrome = rect(12, 12, 366, 52),
            tabs = rect(16, 72, 358, 44),
            board = rect(16, 124, 358, 220),
            grid = rect(21, 158, 348, 148),
            bench = rect(16, 356, 358, 128),
            queue = rect(16, 496, 358, 140),
            sling = rect(16, 648, 358, 92),
            primary = rect(16, 772, 358, 56),
        },
        battle = {
            chrome = rect(12, 12, 366, 52),
            opponent = rect(16, 72, 358, 246),
            event_spine = rect(16, 326, 358, 156),
            player = rect(16, 490, 358, 246),
            controls = rect(16, 744, 358, 84),
        },
        result = {
            chrome = rect(12, 12, 366, 52),
            still_life = rect(16, 80, 358, 196),
            verdict = rect(16, 292, 358, 170),
            ledger = rect(16, 478, 358, 190),
            primary = rect(16, 692, 358, 56),
            review = rect(16, 760, 174, 56),
            replay = rect(200, 760, 174, 56),
        },
    },
    desktop = {
        chrome = rect(24, 16, 1232, 64),
        footer = rect(24, 688, 1232, 88),
        draft = {
            inventory = rect(24, 96, 240, 568),
            offers = rect(288, 96, 968, 568),
        },
        formation = {
            catalog = rect(24, 96, 280, 568),
            board = rect(328, 96, 616, 568),
            loadout = rect(968, 96, 288, 568),
        },
        battle = {
            opponent = rect(24, 96, 500, 568),
            event_spine = rect(548, 96, 184, 568),
            player = rect(756, 96, 500, 568),
        },
        result = {
            still_life = rect(24, 96, 596, 568),
            ledger = rect(644, 96, 612, 568),
        },
    },
}

M.motion = {
    tap_down = 0.070,
    tap_release = 0.150,
    card_deal = 0.180,
    card_stagger = 0.045,
    drag_settle = 0.140,
    volley_commit = 0.240,
    launch = 0.260,
    collision = 0.140,
    brick_destroy = 0.200,
    shell_break = 0.220,
    core_release = 0.280,
    battle_end = 0.400,
    camera_nudge = 3,
    camera_nudge_seconds = 0.090,
    hit_stop = 0.035,
    particle_cap_phone = 48,
    particle_cap_desktop = 96,
    reduced = {
        crossfade = 0.080,
        camera_nudge = 0,
        hit_stop = 0,
        particles = 0,
        positional_tween = 0,
    },
}

-- Cue recipes are contracts for a small procedural PCM generator. Frequency
-- sweeps are linear over the cue. Envelopes use seconds. "noise" uses a local
-- MINSTD stream seeded from cue.seed and never the battle RNG.
M.audio = {
    sample_rate = 22050,
    bit_depth = 16,
    channels = 1,
    master_gain = 0.72,
    cue_cooldown = 0.060,
    cues = {
        ui_select = {
            duration = 0.045, attack = 0.003, release = 0.030, seed = 1103,
            voices = {
                { wave = "sine", from = 740, to = 920, gain = 0.22 },
            },
        },
        sling_release = {
            duration = 0.150, attack = 0.002, release = 0.120, seed = 2207,
            voices = {
                { wave = "triangle", from = 190, to = 82, gain = 0.28 },
                { wave = "noise", from = 0, to = 0, gain = 0.08 },
            },
        },
        brick_hit = {
            duration = 0.110, attack = 0.001, release = 0.095, seed = 3301,
            voices = {
                { wave = "sine", from = 118, to = 74, gain = 0.32 },
                { wave = "noise", from = 0, to = 0, gain = 0.12 },
            },
        },
        shell_break = {
            duration = 0.170, attack = 0.001, release = 0.155, seed = 4409,
            voices = {
                { wave = "sine", from = 2630, to = 1760, gain = 0.11 },
                { wave = "sine", from = 1970, to = 1310, gain = 0.10 },
                { wave = "noise", from = 0, to = 0, gain = 0.15 },
            },
        },
        core_release = {
            duration = 0.260, attack = 0.012, release = 0.190, seed = 5501,
            voices = {
                { wave = "sine", from = 196, to = 392, gain = 0.20 },
                { wave = "sine", from = 294, to = 588, gain = 0.11 },
            },
        },
        result = {
            duration = 0.420, attack = 0.010, release = 0.310, seed = 6607,
            voices = {
                { wave = "sine", from = 261.63, to = 261.63, gain = 0.15 },
                { wave = "sine", from = 329.63, to = 329.63, gain = 0.12 },
                { wave = "sine", from = 392.00, to = 392.00, gain = 0.10 },
            },
        },
    },
}

return M
