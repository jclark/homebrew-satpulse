# homebrew-satpulse

A [Homebrew](https://brew.sh) tap for [SatPulse](https://satpulse.net).

The formulae build from source (Go toolchain required) and run the daemon under
launchd via `brew services`. There are no bottles yet.

## Install

The macOS port is still new, so use a prerelease:

```sh
brew tap jclark/satpulse
brew install jclark/satpulse/satpulse-pre
```

Then edit `/opt/homebrew/etc/satpulse.toml` and start the service:

```sh
brew services run satpulse-pre
```

`satpulse-pre` gives you the latest prerelease that has been tested on macOS.
(If there is no prerelease available, then it will give you the latest release.)

You can also install the latest code on the `master` branch:

```sh
brew install --HEAD jclark/satpulse/satpulse
```

In this case, start the service with:

```sh
brew services run satpulse
```

## Serial devices

The daemon is started under launchd as a per-user LaunchAgent.

With satpulsed on Linux, you have to explicitly specify the serial device to be used.
But on macOS, USB serial device names `/dev/cu.*` change depending on which USB port or hub the device is plugged into.
To make this convenient, launchd is configured to make use of [find-serial](https://github.com/jclark/satpulse/tree/master/macos),
which is a small macOS-specific utility for discovering USB serial devices.
`brew services` calls launchd with a `.plist` file; the `.plist` file references the service wrapper;
the service wrapper loads its config from `find-serial.env`; if that does not disable the use of `find-serial`,
then the service wrapper will call `find-serial` to discover the serial device name and then run `satpulsed` with the discovered serial device name.
This all works automatically provided you have only one USB serial device plugged in.

You can run `find-serial` with no arguments to show the USB serial devices currently recognized. It will print something like

```
device=/dev/cu.usbmodem11301 vid=1546 pid=01A9 model="u-blox GNSS receiver" vendor="u-blox AG - www.u-blox.com"
```

If you have more than one serial device, you can edit `find-serial.env` to match only a specific vendor and product id:

```
FIND_SERIAL_OPTS="--vid 1546 --pid 01A9"
```

## File layout

Everything installs under the Homebrew prefix (`/opt/homebrew` on Apple Silicon,
`/usr/local` on Intel), where `<formula>` is `satpulse` or `satpulse-pre`:

| File | Location |
|---|---|
| `satpulsed` | `<prefix>/sbin/satpulsed` |
| `satpulsetool` | `<prefix>/bin/satpulsetool` |
| `find-serial` | `<prefix>/bin/find-serial` |
| config | `<prefix>/etc/satpulse.toml` (not overwritten on upgrade) |
| service config | `<prefix>/etc/find-serial.env` (not overwritten on upgrade) |
| man pages | `<prefix>/share/man/man{1,5,8}/...` |
| gpsmsg tree | `<prefix>/share/satpulse/gpsmsg/...` |
| logs | `<prefix>/var/log/satpulse/...` |
| service wrapper | `<prefix>/opt/<formula>/libexec/satpulse-service` |
| launchd plist | `<prefix>/opt/<formula>/homebrew.mxcl.<formula>.plist` |

## Maintaining the prerelease channel

Re-pointing the prerelease channel is a two-line edit in
`Formula/satpulse-pre.rb`: set a new `revision` (any commit on `master`) and bump
`version` to a later `0.3-pre-YYYYMMDD` date.
