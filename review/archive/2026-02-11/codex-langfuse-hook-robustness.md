# Langfuse Hook Robustness Review

Date: 2026-02-11  
Scope: Stop hook configured in `~/.claude/settings.json` → `python3 /home/node/.claude/hooks/langfuse_hook.py` (repo source at `infra/hooks/langfuse_hook.py`)

## Key findings

1. **Concurrent write race on state/log files**
   - `save_state()` writes directly to one JSON file with no file lock or atomic rename.
   - Multiple Stop hook invocations can interleave and lose progress (`last_line`, `turn_count`).

2. **Malformed JSONL handling silently drops data**
   - Parse errors are skipped (`continue`) without logging line number/session, making recovery hard.

3. **Incremental state can regress after crashes/partial writes**
   - `load_state()` returns `{}` on decode error (good for non-blocking), but can cause replay/duplication if state file was partially written.

4. **Only latest transcript is processed**
   - `find_latest_transcript()` picks a single most-recent file; concurrent sessions in different project dirs can lag behind until they become latest.

5. **Error logging is partial**
   - Some failures log only in debug mode; non-debug operation may hide root causes for skipped lines or transcript selection issues.

## Actionable recommendations

### 1) Make state writes atomic and locked

Implement:
- lock file (`fcntl.flock`) for read-modify-write cycle.
- write to temp file + `os.replace()`.
- fsync file + parent directory for durability.

Pseudo-pattern:

```python
with open(lock_path, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    current = load_state_safe()
    current[session_id] = updated
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(current))
    os.replace(tmp, STATE_FILE)
```

### 2) Improve malformed JSONL resilience and observability

- Log parse failures with session id + line number + exception.
- Track `bad_line_count` in state for visibility.
- If malformed tail line appears (common during active write), keep cursor at previous valid line and retry next run.

### 3) Prevent duplicate trace emission

Store idempotency markers per turn:
- hash of `(session_id, user_msg_id, assistant_msg_id_sequence, tool_ids)`.
- skip if already processed.

This protects against replay when state resets.

### 4) Process all active transcripts, not only newest

Replace `find_latest_transcript()` with iterator over all `.jsonl` files sorted by mtime.
- Process each session incrementally.
- Persist per-session state as already modeled.

### 5) Expand non-debug logging for critical events

Always log:
- selected session/transcript path
- number of parsed vs skipped lines
- number of emitted turns
- state checkpoint (`last_line`, `turn_count`)

Keep full stack traces behind debug flag.

## Suggested recovery behavior

If `langfuse_state.json` is malformed:
1. Move corrupted file to `langfuse_state.json.corrupt.<timestamp>`.
2. Rebuild minimal state by scanning transcript boundaries.
3. Continue without blocking Claude session.

## Source references

- `~/.claude/settings.json` (Stop hook command path)
- `infra/hooks/langfuse_hook.py:112-126` (state load/save without lock/atomic replace)
- `infra/hooks/langfuse_hook.py:215-258` (single latest transcript selection)
- `infra/hooks/langfuse_hook.py:405-412` (silent JSON parse skip)
- `infra/hooks/langfuse_hook.py:488-495` (single state checkpoint write)
- `infra/hooks/langfuse_hook.py:543-557` (top-level error handling/logging)
