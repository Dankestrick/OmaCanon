# working on OmaCanon

edit the code here, then copy it into the plugins folder and restart the shell (QML only reloads on a restart):

```bash
scripts/dev-install.sh
omarchy restart shell
```

don't restart the shell while photos are coming over, it ends the download (it picks up where it stopped next time).

the helper works from a terminal too:

```bash
helpers/omacanonctl status
helpers/omacanonctl days
```

test mode: these files in `~/.config/omacanon/` (or the same names as env vars) keep tests away from real photos. delete them when you're done.

- `test-home`: a folder that stands in for photos, state and cache (`OMACANON_HOME`)
- `test-limit`: only bring the newest N photos per download (`OMACANON_LIMIT`)
- `test-catalog`: an OmaRAW catalog file to send to instead of yours (`OMACANON_CATALOG`)
