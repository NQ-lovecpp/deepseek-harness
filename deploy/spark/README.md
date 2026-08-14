# Spark deployment

This directory deploys DeepSeek Harness on the Spark host through Docker Compose. The Web UI stays on `127.0.0.1:3080`; Nginx terminates self-signed HTTPS on `127.0.0.1:8891`, and FRP publishes that TLS endpoint on `https://117.72.15.209:12009`.

The Docker build uses the Tsinghua Debian mirror over HTTP because the Spark host's default Debian route stalls during image builds. Debian repository signatures remain verified by APT.

## Security model

- Nginx requires Basic Auth. Generate its password hash and local TLS files before the first start; the clear-text password is never stored in this repository.
- Nginx is the authentication boundary and rewrites the upstream `Host` and `Origin` to DSH's loopback authority. DSH intentionally keeps settings and credentials RPCs loopback-only; forwarding the public FRP authority would make those calls return `403` even after Basic Auth succeeds.
- DSH state, sessions, settings, and credentials live only in the named `dsh-state` Docker volume. The local vLLM placeholder key is not a secret.
- The default `host-admin` permission preset uses `danger-full-access` with `ask`: every action that needs approval requires a fresh browser approval, and a rejected, unattended, or disconnected request does not run.
- The agent can access `/host/chen` and the Docker socket. Docker socket access is equivalent to host-root container control; do not grant approvals to instructions you do not trust.
- `systemctl --user` is forwarded only to a loopback-only chen user service through a randomly generated local token. The proxy accepts a small allowlist of user-service operations and never supplies a root shell.
- Keep host-administration sessions on the local Spark vLLM provider. A cloud provider can receive any host-file content the agent reads while serving a request.

## First start

On Spark, run the following once from this directory. Supply the Nginx password only through the shell environment.

```sh
export NGINX_AUTH_PASSWORD='replace-with-the-approved-password'
./prepare-proxy.sh
./prepare-host-admin.sh
unset NGINX_AUTH_PASSWORD
install -Dm 0644 systemd/deepseek-harness.service ~/.config/systemd/user/deepseek-harness.service
install -Dm 0644 systemd/frpc-deepseek-harness.service ~/.config/systemd/user/frpc-deepseek-harness.service
install -Dm 0644 systemd/deepseek-harness-systemctl-proxy.service ~/.config/systemd/user/deepseek-harness-systemctl-proxy.service
install -Dm 0644 systemd/deepseek-harness-update.service ~/.config/systemd/user/deepseek-harness-update.service
install -Dm 0644 systemd/deepseek-harness-update.timer ~/.config/systemd/user/deepseek-harness-update.timer
systemctl --user daemon-reload
systemctl --user enable --now deepseek-harness.service
systemctl --user enable --now frpc-deepseek-harness.service
systemctl --user enable --now deepseek-harness-systemctl-proxy.service
systemctl --user enable --now deepseek-harness-update.timer
```

The seed settings register Spark vLLM at `http://127.0.0.1:14002/v1` with model ID `/models/Qwen3.6-35B-A3B-NVFP4`. Configure a DeepSeek API key in **Settings → Models**; DSH stores it in `dsh-state`, not Git.

## Operations

```sh
systemctl --user status deepseek-harness.service frpc-deepseek-harness.service
systemctl --user list-timers deepseek-harness-update.timer
systemctl --user start deepseek-harness-update.service
tail -f runtime/update.log
```

The timer checks upstream `master` at 04:30 daily. It uses Spark's existing loopback-only Mihomo proxy for GitHub Smart HTTP and fetches only the upstream tip, avoiding a large history download on each run. It then rebases the local `spark-deploy` commits, builds a SHA-tagged image, replaces DSH only after a health check, and restores the prior commit/image if fetch, rebase, build, or health verification fails. The Spark host has no GitHub write credentials and never pushes this branch.
