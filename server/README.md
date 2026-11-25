# KoopMMO server updates

The KoopMMO plugin (0.76+) reads `latest.json` here every 15 minutes. When `version` is newer than what's
running, it downloads `jar`, checks it against `sha1`, and stages it in the server's `pending-update/` folder.
`koopmmo-launcher.ps1` (run by start.bat) checks the SHA-1 again and installs it at the next restart.

`restart` says when the server restarts for it:
- `when-empty`: as soon as nobody's online (or after 3 hours with a 5-minute countdown)
- `now`: straight away, with a countdown (`countdown` seconds, default 120)
- `manual`: wait for `/mmo update`

Releasing: upload `KoopMMO-pack.zip` first if the pack changed, then the jar, then `latest.json` last.
