## 1. Tests first

- [ ] 1.1 `tests/stub/gh`: answer `api repos/<o>/<r>` from `$GH_STUB/repo.json` (filtered by `-q`), exit 1 when it is missing (`orca-lc test-lock on`, reason in the commit body, `test-lock off`).
- [ ] 1.2 Add `tests/init.test.sh` with cases 1–17 from design.md "Tests"; run it and see them fail.

## 2. orca-lc

- [ ] 2.1 `init_defaults`: the jq object from design.md "Defaults", in `orca.example.json`'s key order.
- [ ] 2.2 Detection helpers per design.md "Detection" and "Languages": project, baseBranch, ticketPattern, tracker (gh through `ghx`, MCP from `.claude.json` and `.mcp.json`), testCommand, gate, stackUp/stackDown, testGlob/sourceGlob.
- [ ] 2.3 `cmd_init`: argument parsing (`--yes`, else exit 2), target `$(main_root)/.orca/config.json`, invalid-JSON refusal, prompt loop per design.md "Prompts" (including the test-only `ORCA_INIT_PROMPT_STDIN=1` with its comment), Rerun rules.
- [ ] 2.4 Output and confirmation per design.md: build the config, `.gitignore` line check, `no changes`, the printout, `[y/N]`, the non-terminal exit 1, atomic write.
- [ ] 2.5 Dispatcher entry and the USAGE line from design.md "Command".

## 3. Docs

- [ ] 3.1 README Quickstart: `orca-lc init` replaces the `mkdir`/`cp`/edit lines; Configuration: one line saying `init` writes and edits the file, and `orca.example.json` is the reference.
- [ ] 3.2 docs/daily-use.md:28: `orca-lc init` replaces the copy.

## 4. Verify

- [ ] 4.1 `bash tests/run.sh` passes, `tests/help.test.sh` included; `orca-lc gate` passes.
- [ ] 4.2 By hand on Linux, in a scratch clone of a real repo: an interactive run, a `--yes` run, and a rerun printing `no changes`.
