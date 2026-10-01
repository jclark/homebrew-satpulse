# homebrew-satpulse

A [Homebrew](https://brew.sh) tap for [SatPulse](https://satpulse.net).

For how to install, configure and run SatPulse on macOS, see
[Setup on macOS](https://satpulse.net/setup/macos.html) on the SatPulse website.

## Formulae

| Formula | Tracks |
|---|---|
| `satpulse-pre` | the latest prerelease tested on macOS (or the latest release, if that is newer) |
| `satpulse` | the `master` branch; install with `--HEAD` |

`satpulse` is head-only until SatPulse 0.3 is released, when it will gain a
stable version tracking the latest release.

`satpulse-pre` is pinned to a specific commit on `master`, with a version of
the form `0.3-pre-YYYYMMDD`.

Both formulae build from source; there are no bottles. Only Apple Silicon is
tested.

## Updating the formulae

`satpulse` follows `master` automatically, so it needs no update.

To re-point `satpulse-pre` to a new prerelease, get the commit and its UTC date:

```sh
gh api repos/jclark/satpulse/commits/<tag-or-sha> --jq '.sha, .commit.committer.date'
```

Then edit the `revision` and `version` in `Formula/satpulse-pre.rb`:

```ruby
url "https://github.com/jclark/satpulse.git",
    revision: "<full 40-character sha>"
version "0.3-pre-YYYYMMDD"
```

The version must increase for `brew upgrade` to pick up the change. There are
no checksums to update: the formulae use git, so the revision is the integrity
check.

After installing, `satpulsetool --version` shows the version and short commit.

When 0.3 is released, add a `stable` block to `Formula/satpulse.rb`
(`url "https://github.com/jclark/satpulse.git", tag: "v0.3", revision: "<sha>"`),
keeping the `head` line.
