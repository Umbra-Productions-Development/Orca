## 1. Docs

- [ ] 1.1 In `skills/orca/SKILL.md`, section "Pull requests", after the sentence ending "stays under `prShareLimit` in `.orca/config.json`.", add: "With `prShareLimit` absent, nothing is counted: no size budget splits the ticket into changes, and each change is its own pull request unless the proposal groups changes into one by decision."
- [ ] 1.2 In `README.md`, extend the `prShareLimit` row's description to: "Size under which small changes may share one PR. Absent: no size counting; changes share a PR only when the proposal groups them"
- [ ] 1.3 Run the gate (`orca-lc gate` or the `gate` string in `.orca/config.json`); it must pass unchanged.
