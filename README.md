# homebrew-satpulse

A [Homebrew](https://brew.sh) tap for [satpulse](https://github.com/jclark/satpulse),
an integrated GPS timing daemon (`satpulsed`) and configuration tool
(`satpulsetool`), packaged for macOS.

The formulae build from source (Go toolchain required) and run the daemon under
launchd via `brew services`. There are no bottles yet.

## Install

```sh
brew tap jclark/satpulse
```

Three maturity tiers are available:

| Channel | Command | What you get |
|---|---|---|
| master tip | `brew install --HEAD jclark/satpulse/satpulse` | the latest commit on `master` |
| prerelease | `brew install jclark/satpulse/satpulse-pre` | latest at >= prerelease stability (a pinned, tested commit) |
| stable | `brew install jclark/satpulse/satpulse` | latest at >= release stability *(available once v0.3 ships)* |

`satpulse` and `satpulse-pre` are rolling channels: each tracks the newest build
at its stability level, so `brew upgrade` keeps you current within a channel.
They are not auto-promoted across channels — to move from `satpulse-pre` to
`satpulse`, switch once with `brew uninstall` / `brew install`. (Pinned
`satpulse@X.Y` version lines, which would upgrade `0.3-pre` -> `0.3` -> `0.3.1`
in place, are Future work.)

Only one channel can be installed at a time — they ship the same binaries.

## Run the daemon

The daemon is started under launchd as a per-user LaunchAgent:

```sh
brew services start jclark/satpulse/satpulse        # or satpulse-pre
```

At launch the service runs `find-serial --exec` to resolve the current
`/dev/cu.*` device and passes it to `satpulsed` as `-d`. The default match is any
USB serial callout device; if you have more than one, edit the `service` block's
`--vid`/`--pid` arguments.

## Layout

Everything installs under the Homebrew prefix (`/opt/homebrew` on Apple Silicon,
`/usr/local` on Intel), except the launchd plist:

| File | Location |
|---|---|
| `satpulsed` | `<prefix>/sbin/satpulsed` |
| `satpulsetool` | `<prefix>/bin/satpulsetool` |
| `find-serial` | `<prefix>/bin/find-serial` |
| config | `<prefix>/etc/satpulse.toml` (not overwritten on upgrade) |
| man pages | `<prefix>/share/man/man{1,5,8}/...` |
| gpsmsg tree | `<prefix>/share/satpulse/gpsmsg/...` |
| logs | `<prefix>/var/log/satpulse/...` |
| launchd plist | `~/Library/LaunchAgents/homebrew.mxcl.satpulse.plist` |

## Maintaining the prerelease channel

Re-pointing the prerelease channel is a two-line edit in
`Formula/satpulse-pre.rb`: set a new `revision` (any commit on `master`) and bump
`version` to a later `0.3-pre-YYYYMMDD` date.
