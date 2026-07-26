-- battle/tests/harness.lua — a tiny assertion harness.
--
-- No external test framework: CI installs plain lua5.1 and nothing else, and a
-- dependency here would be a dependency on the critical path of every build.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = table.concat({
    here .. "/../../?.lua",
    here .. "/../?.lua",
    "./?.lua",
    package.path,
}, ";")

local H = {}

local Case = {}
Case.__index = Case

function H.new_case(name)
    return setmetatable({ name = name, checks = 0, failures = {} }, Case)
end

function Case:fail(message)
    self.failures[#self.failures + 1] = message
    print(string.format("  FAIL [%s] %s", self.name, message))
end

function Case:ok(condition, message)
    self.checks = self.checks + 1
    if not condition then
        self:fail(message or "assertion failed")
    end
    return condition
end

function Case:eq(actual, expected, message)
    self.checks = self.checks + 1
    if actual ~= expected then
        self:fail(string.format("%s — expected %s, got %s",
            message or "values differ", tostring(expected), tostring(actual)))
        return false
    end
    return true
end

function Case:neq(actual, unexpected, message)
    self.checks = self.checks + 1
    if actual == unexpected then
        self:fail(string.format("%s — expected something other than %s",
            message or "values should differ", tostring(unexpected)))
        return false
    end
    return true
end

--- Assert that `fn` raises, and that the message contains `pattern` (plain
--- substring, not a Lua pattern).
function Case:raises(fn, pattern, message)
    self.checks = self.checks + 1
    local ok, err = pcall(fn)
    if ok then
        self:fail((message or "expected an error") .. " — but the call succeeded")
        return false
    end
    if pattern and not tostring(err):find(pattern, 1, true) then
        self:fail(string.format("%s — error %q does not contain %q",
            message or "wrong error", tostring(err), pattern))
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Log helpers shared by the test modules
-- ---------------------------------------------------------------------------

--- Every event matching a predicate, in log order.
function H.select(log, predicate)
    local out = {}
    for _, event in ipairs(log.events) do
        if predicate(event) then out[#out + 1] = event end
    end
    return out
end

function H.of_type(log, kind, side)
    return H.select(log, function(event)
        return event.type == kind and (side == nil or event.side == side)
    end)
end

--- Render a slice of the log, for failure messages.
function H.dump(log, limit)
    local lines = log:lines()
    local out = {}
    for index = 1, math.min(#lines, limit or 40) do out[index] = lines[index] end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------

--- Run a list of {name, run} modules. Exits non-zero if anything failed.
function H.run(modules)
    local total_checks, total_failures, failed_cases = 0, 0, 0
    for _, module in ipairs(modules) do
        local case = H.new_case(module.name)
        local ok, err = pcall(module.run, case)
        if not ok then
            case:fail("test raised: " .. tostring(err))
        end
        total_checks = total_checks + case.checks
        total_failures = total_failures + #case.failures
        if #case.failures > 0 then
            failed_cases = failed_cases + 1
            print(string.format("FAIL %-28s %d check(s), %d failure(s)", module.name, case.checks, #case.failures))
        else
            print(string.format("ok   %-28s %d check(s)", module.name, case.checks))
        end
    end

    print("")
    if total_failures == 0 then
        print(string.format("OK: %d checks across %d test files", total_checks, #modules))
        os.exit(0)
    end
    print(string.format("FAILED: %d failure(s) in %d of %d test files", total_failures, failed_cases, #modules))
    os.exit(1)
end

--- Run one module directly, for `lua5.1 battle/tests/test_foo.lua`.
function H.run_one(module)
    H.run({ module })
end

return H
