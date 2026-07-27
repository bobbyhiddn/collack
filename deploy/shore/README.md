# Shore deployment

These files keep the reviewed Callack release running as a rootless Podman
container and keep Shore's `/collack/` proxy registration current.

The service is pinned to image digest
`sha256:38ca764b0e9e5447f346dfebba6f655b8bed27df0d4d20e75193acbe834185d1`,
whose image label identifies source revision
`40335c00e80b9755235f09bcd0d6e56347363177`. It binds only
`127.0.0.1:7912`, waits for Podman's health notification before becoming
active, and restarts when the health check kills an unhealthy container.

`register-callack-route.sh` uses Shore's user-level dynamic registration API.
The main service force-registers after every start. The timer then reconciles
the exact route once per minute, but posts only if the registration is missing,
different, not proxying successfully, or older than the current Shore process.
That last check makes Shore re-announce Callack to Dock after Shore restarts.

Install from the repository root:

```bash
systemctl --user link "$PWD/deploy/shore/callack-release.service"
systemctl --user link "$PWD/deploy/shore/callack-route-reconcile.service"
systemctl --user link "$PWD/deploy/shore/callack-route-reconcile.timer"
systemctl --user daemon-reload
systemctl --user enable callack-release.service callack-route-reconcile.timer
systemctl --user restart callack-release.service
systemctl --user start callack-route-reconcile.timer
```

Inspect the durable state:

```bash
systemctl --user is-enabled callack-release.service callack-route-reconcile.timer
systemctl --user status callack-release.service callack-route-reconcile.timer
systemctl --user list-timers callack-route-reconcile.timer
curl --fail http://127.0.0.1:7778/api/dock/services
curl --fail --head http://127.0.0.1:7778/collack/
```

Exercise the live Shore route in a mobile browser:

```bash
PLAYWRIGHT_BROWSERS_PATH=.playwright-browsers \
  node deploy/shore/verify-live-route.mjs
```

The user manager must have lingering enabled for startup before an interactive
login. Confirm that prerequisite with `loginctl show-user "$USER" -p Linger`.
