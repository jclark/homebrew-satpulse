# homebrew-satpulse

A [Homebrew](https://brew.sh) tap for [SatPulse](https://satpulse.net).

For how to install, configure and run SatPulse on macOS, see
[Setup on macOS](https://satpulse.net/setup/macos.html) on the SatPulse website.

## Formulae

| Formula | Tracks |
|---|---|
| `satpulse-pre` | the latest prerelease tested on macOS (or the latest release, if that is newer) |
| `satpulse` | the latest release; with `--HEAD`, the `master` branch |

`satpulse-pre` is pinned to a specific commit on `master`, with a version of
the form `0.4-pre-YYYYMMDD`, or the release version when it tracks a release.

Both formulae build from source; there are no bottles. Only Apple Silicon is
tested.

## Updating the formulae

`satpulse --HEAD` follows `master` automatically, so it needs no update.

To re-point `satpulse-pre` to a new prerelease, such as `v0.4-pre-20261201`,
edit two lines in `Formula/satpulse-pre.rb`:

- `revision`: the full 40-character sha of the commit that the prerelease tag
  points to (the GitHub release page links to it)
- `version`: the tag name without the leading `v`, e.g. `0.4-pre-20261201`

```ruby
url "https://github.com/jclark/satpulse.git",
    revision: "<full 40-character sha>"
version "0.4-pre-YYYYMMDD"
```

The version must increase for `brew upgrade` to pick up the change. There are
no checksums to update: the formulae use git, so the revision is the integrity
check.

After installing, `satpulsetool --version` shows the version and short commit.

When a release is published, update the `tag` and `revision` in
`Formula/satpulse.rb` to the release tag and the commit it points to, and
re-point `satpulse-pre` to the same commit with the release version, e.g. `0.3`.
Homebrew orders `0.3-pre-YYYYMMDD` before `0.3`, so `brew upgrade` picks it up.
