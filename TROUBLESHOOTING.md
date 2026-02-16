# Troubleshooting

Common issues when building or running the No More Configs devcontainer.

---

## Docker / WSL2

### No space left on device

```
tar: write error: No space left on device
```

The WSL2 virtual disk used by Docker Desktop is full. This isn't caused by the NMC image (~2-2.5 GB) — it's likely from accumulated Docker images, containers, build cache, and volumes.

**Fix:**

```powershell
# From a Windows terminal — remove unused Docker data
docker system prune -a

# If still low, shut down WSL and compact the virtual disk
wsl --shutdown
# Then in PowerShell as admin:
Optimize-VHD -Path "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx" -Mode Full
```

### docker-credential-desktop not found

```
error getting credentials - err: exec: "docker-credential-desktop": executable file not found in %PATH%
```

Docker can't find its credential helper, so `docker pull` fails repeatedly. Common on Docker Desktop for Windows.

**Fix:** Edit `C:\Users\<you>\.docker\config.json`:

- Change `"credsStore": "desktop"` to `"credsStore": "desktop.exe"`
- Or remove the `"credsStore"` line entirely (the base image `node:20` is public and doesn't need authentication)

### MinIO fails to start — permission denied

```
mkdir: cannot create directory '/data/langfuse': Permission denied
```

The Chainguard MinIO image runs as UID `65532`, but the data directory is owned by the container user (`node`, UID `1000`). This was caused by the `langfuse-setup` script using a `busybox` container to chown directories — in Docker-outside-of-Docker, the volume paths don't resolve to the same filesystem, so the chown targets a phantom directory.

**Fixed in v1.0.1.** If you're on an older version, update or run manually:

```bash
sudo chown -R 65532:65532 /workspace/infra/data/minio
sudo chown -R 101:101 /workspace/infra/data/clickhouse
```

### Docker socket permission denied

```
permission denied while trying to connect to the Docker daemon socket
```

The bind-mounted Docker socket doesn't have the right permissions inside the container.

**Fix:** Run inside the container:

```bash
sudo chmod 666 /var/run/docker.sock
```

---

## Networking

### Langfuse unreachable / port 3052 blocked

WSL2 networking can break after sleep/resume or network changes, making `host.docker.internal` unreachable.

**Fix:** PowerShell as admin:

```powershell
wsl --shutdown
Restart-Service hns
```

Then reopen VS Code and rebuild the container.

### Traces not appearing in Langfuse

**Check these in order:**

1. `echo $TRACE_TO_LANGFUSE` inside a Claude session — should be `true`
2. `curl http://host.docker.internal:3052/api/public/health` — should return OK
3. `tail -20 ~/.claude/state/langfuse_hook.log` — check for errors

---

## File System

### ENOENT on files that exist

WSL2's 9P bind mount can serve stale metadata intermittently. Re-reading the file or retrying the operation resolves it. This is a known WSL2 issue and is self-healing.
