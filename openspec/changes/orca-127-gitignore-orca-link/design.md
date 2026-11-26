## Fix

Replace the `.gitignore` line `.orca/` with `.orca`. Without a slash, the pattern matches a file, directory or symlink named `.orca` at any depth, which covers the main checkout's directory and each worktree's link. The repository has no other path named `.orca`, so the wider match hides nothing.

In `README.md` § Configuration, after "`.orca/config.json`, one per repository, never committed.", add: "Its `.gitignore` line is `.orca`, with no trailing slash: `.orca/` matches directories only and misses the `.orca` symlink in each worktree."

## Verification

No automated test. In this worktree, where `.orca` is the symlink, after the change:

- `git status --porcelain` lists no `.orca` entry.
- `git check-ignore -v .orca` names the `.gitignore` line `.orca`.

## Decisions

- The pattern is `.orca`, not `/.orca`: it matches what the issue asks for and what `orca-lc init` writes for adopting repositories. — user (recommended, accepted)
- The explanation goes in the README Configuration paragraph only, with no comment in `.gitignore`. — user (recommended, accepted)
- No new test. Verification is a manual `git status` / `git check-ignore` check in a worktree, recorded in tasks.md. `init.test.sh` already covers the adopting-repo case. — user (recommended, accepted)
- One change with no spec delta (there is no specs baseline until #62) and one PR. — user (recommended, accepted)

## Risks

None known. The change only widens an ignore pattern for a path that is never committed.
