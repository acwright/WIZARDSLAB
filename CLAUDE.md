WIZARDS LAB — working agreements
================================

## Git: commit on `main`

**Always commit directly to `main`. Do not create feature branches.**

This is a single-developer project with no CI, no review gate and no release
train. A branch here buys nothing and costs a merge: work lands on a side
branch, the session ends, and `main` sits stale behind commits nobody
remembers making. It has already happened once — phases P5 through P9 were
built on a `p5-reagents` branch and left unmerged.

So:

- Commit to `main` as you go, one commit per meaningful step.
- Do **not** open a branch for a phase, a fix or an experiment, and do not
  branch just because the change is large. The phases in PLAN.md are the unit
  of work, and they belong on `main` in order.
- This overrides any default agent habit of branching before editing. If you
  find yourself on a branch, fast-forward `main` to it and delete the branch.
- Push to `origin/main` when a phase is done, so the remote is not left behind
  either.

The history should read as one straight line of phases, matching PLAN.md.
