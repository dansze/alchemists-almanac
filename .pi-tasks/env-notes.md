769 lines, 31217 bytes at expected path, valid Markdown structure	TASK_0001	mu6gu6so-29iauwvb	doc
VERIFY block uses BRE alternation `(load|init)` with `grep -qi` — literal parens, not regex groups. Correct form is `grep -Eiq`.	TASK_0001	mu6gu6so-29iauwvb	verify-bug
The `grep -qF "Phase [0-9]"` pattern is a false negative — `-F` (fixed string) treats `[0-9]` as literal text, not a digit class. The file does contain "Phase 1", "Phase 2", "Phase 3" as confirmed by `grep -E "Phase [0-9]"`.	TASK_0002	mu7tju21-unelb32z	verify-script
OpenMW binary found at `/home/dsze/.local/bin/openmw`, loaded mod directory without Lua errors	TASK_0004	mu8vo0tp-ce51sh49	openmw:version
`luac -p` correctly rejects syntax errors (exit code 1)	TASK_0004	mu8vo0tp-ce51sh49	negative-control:luac
luac 5.5 available at `/home/dsze/.local/share/mise/installs/lua/latest/bin/luac`, correctly validates Lua 5.5 syntax	TASK_0006	mu9064wr-l1mfbida	lua:luac
`openmw.*` Lua modules are compiled into the OpenMW binary and not available as standalone Lua packages; verification used mock modules in `/tmp` to test the real shipped artifact	TASK_0006	mu9064wr-l1mfbida	lua:openmw
The spec's sharedIngredients regex `^[a-zA-Z0-9_]+(:[a-zA-Z0-9_]+)*$` is invalid for Lua patterns — `*` cannot follow capture groups in Lua's pattern grammar. The actual data is correctly formatted.	TASK_0006	mu9064wr-l1mfbida	verify:lua-pattern-bug
luac 5.5.1 available at `/home/dsze/.local/share/mise/installs/lua/latest/bin/luac`, correctly validates Lua 5.5 syntax.	TASK_0009	mu9cnbgm-qhs7wri0	lua:5.5.1
