# Working on this tap

This is a Homebrew tap (`jclark/satpulse`, repo `homebrew-satpulse`) packaging
the macOS build of [satpulse](https://github.com/jclark/satpulse). Two formulae,
both built from source.

## Layout

- `Formula/satpulse.rb` — rolling ">= release" channel. **Head-only** (a `head`
  line, no `stable` block) until satpulse v0.3 ships.
- `Formula/satpulse-pre.rb` — rolling ">= prerelease" channel. A normal `stable`
  formula pinned to a `revision` on satpulse `master`, with an explicit
  `version "0.3-pre-YYYYMMDD"`. Re-pointing it is a two-line edit (revision +
  version).
- `lib/satpulse_formula.rb` — the **shared body**. Both formulae
  `include SatpulseFormula`; it contributes the dependencies, `install`,
  `service`, `caveats`, and `test`. **Change shared behaviour here, not in the
  two formula files**, which only declare their own `desc`, `homepage`, and
  download spec. (`homepage` must stay in each formula file — brew's Homepage
  audit is AST-based and can't see it inside the module.)
- `.github/workflows/test.yml` — CI.

## The satpulse source repo

The formulae fetch satpulse from `https://github.com/jclark/satpulse.git` at
build time (`head` clones `master`; `satpulse-pre` clones its pinned `revision`).
**Do not assume a local checkout of the satpulse repo exists, and do not
hard-code a path to it.** If you need to read satpulse sources, find an existing
checkout or clone the repo into a temp dir.

`def install` depends on these satpulse files, so changes there can require
formula updates:
- `unix-build.sh` — builds the Go binaries (derives version from git; needs a
  real clone with `.git`, which the git download strategy provides).
- `macos/Makefile` / `macos/find-serial.c` — the `find-serial` C tool.
- `docs/man/*.md` — rendered to man pages with pandoc (`unix-build.sh` does NOT
  generate man pages; only the Makefile does, so the formula runs pandoc itself).
- `configs/satpulse.toml` — installed as the default config, with edits applied
  at install time (schema path, `log.dir` under the prefix, and a rewrite of the
  systemd-specific comment above `#device`).
- `configs/gpsmsg` and `configs/config-schema.json` — installed under
  `share/satpulse` (use `share/"satpulse"`, NOT `pkgshare`, which would be
  `share/satpulse-pre` for that formula).

## Pinned Go version

The build pins `depends_on "go@1.25" => :build` to match satpulse's tested Go
(`go.mod: go 1.25.0`; its CI uses `go-version 1.25.x`). Plain `go` tracks the
newest Homebrew Go, which the project does not test. `go@1.26` can't be used: it
is only an alias for `go`, and `brew audit` rejects depending on an alias. Bump
this only when satpulse moves to a Go line that has a real `go@N.NN` formula.

## Local testing — and the HOMEBREW_NO_AUTO_UPDATE gotcha

`brew tap jclark/satpulse "$PWD"` makes a **git clone** of this repo at
`$(brew --prefix)/Library/Taps/jclark/homebrew-satpulse`. The clone reflects the
last **commit**, not your working tree — so after committing you must re-tap to
refresh it.

**Always export `HOMEBREW_NO_AUTO_UPDATE=1` while developing here.** Before each
`install`/`tap`, Homebrew normally auto-runs `brew update`, which does a
`git fetch` + merge on every tap **including this local clone**. If your local
history has diverged from the clone (which happens after rebases/force-pushes,
but also routinely), that merge can leave **conflict markers in the tapped
clone** — which then break `brew style`/`brew install` with Ruby syntax errors
that are NOT present in your actual files. Disabling auto-update avoids this (and
is faster).

Reliable loop:

    export HOMEBREW_NO_AUTO_UPDATE=1
    # edit files, commit
    brew untap jclark/satpulse 2>/dev/null; brew tap jclark/satpulse "$PWD"
    brew style jclark/satpulse
    brew install --HEAD --build-from-source jclark/satpulse/satpulse   # or satpulse-pre

Notes:
- `brew style` lints only Ruby. **actionlint** (which lints
  `.github/workflows/*.yml`, e.g. shellcheck SC2046 on `run:` scripts) runs only
  under `brew test-bot --only-tap-syntax`, like CI — run that to catch workflow
  issues locally.
- `satpulsed` installs into `sbin` (often not on PATH); invoke it as
  `"$(brew --prefix)/sbin/satpulsed"`.
- `brew uninstall` / upgrade never overwrites `etc/satpulse.toml`; remove it
  manually if you need a fresh default.
- When done, untap and uninstall so the machine isn't left on the local-path
  tap: `brew untap jclark/satpulse; brew uninstall satpulse satpulse-pre`.

## CI

`.github/workflows/test.yml` runs on PRs and pushes to `main`:
- `syntax`: `brew test-bot --only-tap-syntax` (style + actionlint + audit).
- `test` (macos-15, Apple Silicon only — the project does not test/ship Intel):
  builds both channels `--build-from-source` and runs hardware-free smoke tests
  (`satpulsetool --version`, `satpulsed --help`, `find-serial --help`).

`setup-homebrew` auto-taps and trusts this repo from the checkout — do NOT add a
manual `brew tap` step (it causes a "Tap remote mismatch" failure).

## Conventions

- **Regular commits only** — no history rewrites, no force-pushes.
- No `Co-Authored-By` trailer (`.claude/settings.json` sets
  `includeCoAuthoredBy: false`).
- macOS-specific end-user documentation belongs in the **satpulse repo**, not
  here.
