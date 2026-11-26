## Change

Last line of `install.sh`:

```
echo "per project: run orca-lc init in the repository"
```

The `per project:` prefix stays, so the line still reads as the closing instruction and `t_fail_installer`'s existing prefix check keeps holding. `init` resolves the main checkout itself (`<main checkout>/.orca/config.json`), so "in the repository" is enough; no worktree caveat is needed.

## Test

`tests/install.test.sh` `t_fail_installer` (case 5.7) is the one case that reads the closing line. Its last assert becomes, on the same `tail -n1` of stdout:

- contains `per project: run orca-lc init in the repository`;
- does not contain `orca.example.json`.

This is a test edit: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`.

## Decisions

- Closing line reads `per project: run orca-lc init in the repository` — user (recommended, accepted).
- Tighten `t_fail_installer`'s closing-line assert to the new text and against `orca.example.json`, under the test lock — user (recommended, accepted).
- README, docs/daily-use.md, skills and agents need no change; they already point at `orca-lc init` — propose, from exploration.
- One change, no spec delta, one PR — propose (no `openspec/specs` baseline until #62).
