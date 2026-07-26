-- battle/tests/test_purity.lua — battle/ stays engine-independent.
--
-- The simulation has to run under plain lua or luajit from the CLI so CI can
-- test it headlessly, which means no love.* anywhere in battle/. It also has to
-- be reproducible, which means no math.random and no wall-clock reads. Those
-- are easy rules to break by accident months from now, so they are a test
-- rather than a comment.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local harness = require("battle.tests.harness")

local M = { name = "purity" }

-- Substrings that must not appear in engine source. The test files themselves
-- are exempt: they legitimately use io to read source and os.exit to report.
local BANNED = {
    { needle = "love.", why = "LOVE runtime call — battle/ must run under plain lua" },
    { needle = "math.random", why = "non-reproducible randomness — use battle/rng.lua" },
    { needle = "os.time", why = "wall clock read — breaks determinism" },
    { needle = "os.clock", why = "wall clock read — breaks determinism" },
    { needle = "require(\"love", why = "LOVE dependency" },
}

local function list_sources()
    local pipe = io.popen("find battle -name '*.lua' -not -path 'battle/tests/*' 2>/dev/null")
    if not pipe then return nil end
    local files = {}
    for line in pipe:lines() do
        files[#files + 1] = line
    end
    pipe:close()
    return files
end

function M.run(t)
    local files = list_sources()
    if not files or #files == 0 then
        t:fail("could not enumerate battle/*.lua — run the tests from the repository root")
        return
    end
    t:ok(#files >= 8, string.format("found %d engine source files", #files))

    for _, path in ipairs(files) do
        local handle = io.open(path, "r")
        if not handle then
            t:fail("could not open " .. path)
        else
            local source = handle:read("*a")
            handle:close()
            for _, rule in ipairs(BANNED) do
                local found = source:find(rule.needle, 1, true)
                -- Comments are allowed to name the banned thing; code is not.
                -- Strip full-line comments before scanning.
                if found then
                    local offending = nil
                    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
                        local stripped = line:gsub("^%s*%-%-.*$", "")
                        if stripped:find(rule.needle, 1, true) then
                            offending = line
                            break
                        end
                    end
                    if offending then
                        t:fail(string.format("%s contains %q (%s):\n    %s",
                            path, rule.needle, rule.why, offending))
                    end
                end
            end
            t:ok(true, path .. " is engine-independent")
        end
    end

    -- The CLI harness must be runnable, and must not need LOVE to be.
    local cli = io.open("battle/cli.lua", "r")
    t:ok(cli ~= nil, "battle/cli.lua exists")
    if cli then cli:close() end
end

if arg and arg[0] and arg[0]:find("test_purity.lua", 1, true) then
    harness.run_one(M)
end

return M
