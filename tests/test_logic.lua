-- Backward-compatible CI entry point. The legacy paddle logic no longer
-- exists; the plain-Lua client suite now verifies the battle-log adapter.
dofile("tests/test_presentation.lua")
