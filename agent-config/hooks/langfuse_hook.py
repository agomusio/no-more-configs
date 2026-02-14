#!/usr/bin/env python3
"""
Langfuse Hook for Claude Code

Captures Claude Code conversations as structured traces in Langfuse.
Runs as a Stop hook — after each assistant response.

What gets captured:
- User prompts (full text)
- Assistant responses (full text)
- Tool invocations (name, input, output)
- Session grouping
- Model info and timing

Opt-in: Only runs when TRACE_TO_LANGFUSE=true is set.
Graceful failure: All errors exit 0 (non-blocking).
"""

import fcntl
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from langfuse import Langfuse
except ImportError:
    print("Error: langfuse package not installed. Run: pip install langfuse", file=sys.stderr)
    sys.exit(0)

# Configuration
LOG_FILE = Path.home() / ".claude" / "state" / "langfuse_hook.log"
STATE_FILE = Path.home() / ".claude" / "state" / "langfuse_state.json"
LOCK_FILE = Path.home() / ".claude" / "state" / "langfuse_state.lock"
DEBUG = os.environ.get("CC_LANGFUSE_DEBUG", "").lower() == "true"
LOG_MAX_SIZE_BYTES = 10 * 1024 * 1024  # 10MB max log size
LOG_BACKUP_COUNT = 3  # Keep 3 rotated logs
REDACT_SECRETS = os.environ.get("CC_LANGFUSE_REDACT", "true").lower() == "true"

# Patterns for secret redaction (conservative - only obvious secrets)
SECRET_PATTERNS = [
    (r'sk-[a-zA-Z0-9]{20,}', 'sk-[REDACTED]'),  # OpenAI/Anthropic keys
    (r'sk-lf-[a-zA-Z0-9-]{20,}', 'sk-lf-[REDACTED]'),  # Langfuse keys
    (r'Bearer [a-zA-Z0-9._-]{20,}', 'Bearer [REDACTED]'),  # Bearer tokens
    (r'token["\']?\s*[:=]\s*["\']?[a-zA-Z0-9._-]{20,}', 'token: [REDACTED]'),  # Generic tokens
    (r'password["\']?\s*[:=]\s*["\']?[^\s"\']{8,}', 'password: [REDACTED]'),  # Passwords
    (r'api[_-]?key["\']?\s*[:=]\s*["\']?[a-zA-Z0-9._-]{16,}', 'api_key: [REDACTED]'),  # API keys
]


def rotate_log_if_needed() -> None:
    """Rotate log file if it exceeds max size."""
    if not LOG_FILE.exists():
        return
    try:
        if LOG_FILE.stat().st_size > LOG_MAX_SIZE_BYTES:
            # Rotate existing backups
            for i in range(LOG_BACKUP_COUNT - 1, 0, -1):
                old = LOG_FILE.with_suffix(f".log.{i}")
                new = LOG_FILE.with_suffix(f".log.{i + 1}")
                if old.exists():
                    old.rename(new)
            # Rotate current log
            LOG_FILE.rename(LOG_FILE.with_suffix(".log.1"))
    except (IOError, OSError):
        pass  # Ignore rotation errors


def log(level: str, message: str) -> None:
    """Log a message to the log file."""
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    rotate_log_if_needed()
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"{timestamp} [{level}] {message}\n")


def debug(message: str) -> None:
    """Log a debug message (only if DEBUG is enabled)."""
    if DEBUG:
        log("DEBUG", message)


def sanitize_text(text: str) -> str:
    """Redact potential secrets from text content.

    This applies conservative patterns to avoid sending API keys,
    passwords, and tokens to Langfuse. Can be disabled by setting
    CC_LANGFUSE_REDACT=false.
    """
    if not REDACT_SECRETS or not text:
        return text

    result = text
    for pattern, replacement in SECRET_PATTERNS:
        result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
    return result


def sanitize_value(value: Any) -> Any:
    """Recursively sanitize a value (string, dict, or list)."""
    if isinstance(value, str):
        return sanitize_text(value)
    elif isinstance(value, dict):
        return {k: sanitize_value(v) for k, v in value.items()}
    elif isinstance(value, list):
        return [sanitize_value(item) for item in value]
    return value


def load_state() -> dict:
    """Load the state file with corruption recovery.

    If the state file is malformed, backs it up and returns empty state.
    """
    if not STATE_FILE.exists():
        return {}
    try:
        data = json.loads(STATE_FILE.read_text())
        if not isinstance(data, dict):
            raise ValueError("State file root is not a dict")
        return data
    except (json.JSONDecodeError, ValueError, IOError) as e:
        # Back up corrupted state file
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        corrupt_path = STATE_FILE.with_suffix(f".json.corrupt.{ts}")
        try:
            STATE_FILE.rename(corrupt_path)
            log("WARN", f"Corrupt state file moved to {corrupt_path}: {e}")
        except OSError:
            log("WARN", f"Corrupt state file could not be backed up: {e}")
        return {}


def save_state(state: dict) -> None:
    """Save state atomically with file locking.

    Uses fcntl.flock for mutual exclusion and atomic rename for crash safety.
    """
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = STATE_FILE.with_suffix(".json.tmp")
    try:
        with open(LOCK_FILE, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            tmp_file.write_text(json.dumps(state, indent=2))
            os.replace(str(tmp_file), str(STATE_FILE))
    except (IOError, OSError) as e:
        log("ERROR", f"Failed to save state: {e}")
        # Clean up temp file on failure
        try:
            tmp_file.unlink(missing_ok=True)
        except OSError:
            pass


def get_content(msg: dict) -> Any:
    """Extract content from a message."""
    if isinstance(msg, dict):
        if "message" in msg:
            return msg["message"].get("content")
        return msg.get("content")
    return None


def is_tool_result(msg: dict) -> bool:
    """Check if a message contains tool results."""
    content = get_content(msg)
    if isinstance(content, list):
        return any(
            isinstance(item, dict) and item.get("type") == "tool_result"
            for item in content
        )
    return False


def get_tool_calls(msg: dict) -> list:
    """Extract tool use blocks from a message."""
    content = get_content(msg)
    if isinstance(content, list):
        return [
            item for item in content
            if isinstance(item, dict) and item.get("type") == "tool_use"
        ]
    return []


def get_text_content(msg: dict) -> str:
    """Extract text content from a message."""
    content = get_content(msg)
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        text_parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text_parts.append(item.get("text", ""))
            elif isinstance(item, str):
                text_parts.append(item)
        return "\n".join(text_parts)
    return ""


def merge_assistant_parts(parts: list) -> dict:
    """Merge multiple assistant message parts into one."""
    if not parts:
        return {}

    merged_content = []
    for part in parts:
        content = get_content(part)
        if isinstance(content, list):
            merged_content.extend(content)
        elif content:
            merged_content.append({"type": "text", "text": str(content)})

    result = parts[0].copy()
    if "message" in result:
        result["message"] = result["message"].copy()
        result["message"]["content"] = merged_content
    else:
        result["content"] = merged_content

    return result


def extract_project_name(project_dir: Path) -> str:
    """Extract a human-readable project name from Claude's project directory name.

    Claude Code stores transcripts in directories named like:
    -Users-username-project-name

    We extract the project name portion.
    """
    dir_name = project_dir.name
    parts = dir_name.split("-")
    if len(parts) > 3:
        # Skip the first 3 parts (-Users-username) and join the rest
        project_parts = parts[3:]
        return "-".join(project_parts)
    return dir_name


def find_all_transcripts() -> list[tuple[str, Path, str]]:
    """Find all transcript files across all project directories.

    Claude Code stores transcripts as .jsonl files in:
    ~/.claude/projects/<project-dir>/<session-id>.jsonl

    Returns: list of (session_id, transcript_path, project_name), sorted by mtime (oldest first)
    """
    projects_dir = Path.home() / ".claude" / "projects"

    if not projects_dir.exists():
        debug(f"Projects directory not found: {projects_dir}")
        return []

    transcripts = []

    for project_dir in projects_dir.iterdir():
        if not project_dir.is_dir():
            continue
        for transcript_file in project_dir.glob("*.jsonl"):
            try:
                mtime = transcript_file.stat().st_mtime
                first_line = transcript_file.read_text().split("\n")[0]
                first_msg = json.loads(first_line)
                session_id = first_msg.get("sessionId", transcript_file.stem)
                project_name = extract_project_name(project_dir)
                transcripts.append((session_id, transcript_file, project_name, mtime))
            except (json.JSONDecodeError, IOError, IndexError) as e:
                debug(f"Skipping unreadable transcript {transcript_file}: {e}")
                continue

    # Sort by mtime ascending (oldest first) so newest state is written last
    transcripts.sort(key=lambda t: t[3])

    return [(sid, path, proj) for sid, path, proj, _ in transcripts]


def create_trace(
    langfuse: Langfuse,
    session_id: str,
    turn_num: int,
    user_msg: dict,
    assistant_msgs: list,
    tool_results: list,
    project_name: str = "",
) -> None:
    """Create a Langfuse trace for a single conversation turn.

    A turn consists of:
    - User message
    - Assistant response(s)
    - Tool calls (if any)
    - Tool results (if any)

    The trace is structured as:
    - Trace (top-level container)
      - Generation span (Claude's response)
      - Tool spans (one per tool call)
    """
    user_text = sanitize_text(get_text_content(user_msg))

    # Get final assistant output
    final_output = ""
    if assistant_msgs:
        final_output = sanitize_text(get_text_content(assistant_msgs[-1]))

    # Extract model info from first assistant message
    model = "claude"
    if assistant_msgs and isinstance(assistant_msgs[0], dict) and "message" in assistant_msgs[0]:
        model = assistant_msgs[0]["message"].get("model", "claude")

    # Collect all tool calls with their results
    all_tool_calls = []
    for assistant_msg in assistant_msgs:
        tool_calls = get_tool_calls(assistant_msg)
        for tool_call in tool_calls:
            tool_name = tool_call.get("name", "unknown")
            tool_input = tool_call.get("input", {})
            tool_id = tool_call.get("id", "")

            # Find matching tool result
            tool_output = None
            for tr in tool_results:
                tr_content = get_content(tr)
                if isinstance(tr_content, list):
                    for item in tr_content:
                        if isinstance(item, dict) and item.get("tool_use_id") == tool_id:
                            tool_output = item.get("content")
                            break

            all_tool_calls.append({
                "name": tool_name,
                "input": sanitize_value(tool_input),
                "output": sanitize_value(tool_output),
                "id": tool_id,
            })

    # Build tags for filtering
    tags = ["claude-code"]
    if project_name:
        tags.append(project_name)

    # Create the trace with spans for each tool call
    with langfuse.start_as_current_span(
        name=f"Turn {turn_num}",
        input={"role": "user", "content": user_text},
        metadata={
            "source": "claude-code",
            "turn_number": turn_num,
            "project": project_name,
        },
    ) as trace_span:
        # Update trace-level metadata
        langfuse.update_current_trace(
            session_id=session_id,
            tags=tags,
            metadata={
                "source": "claude-code",
                "turn_number": turn_num,
                "session_id": session_id,
                "project": project_name,
            },
        )

        # Create generation span for Claude's response
        with langfuse.start_as_current_observation(
            name="Claude Response",
            as_type="generation",
            model=model,
            input={"role": "user", "content": user_text},
            output={"role": "assistant", "content": final_output},
            metadata={"tool_count": len(all_tool_calls)},
        ):
            pass

        # Create spans for each tool call
        for tool_call in all_tool_calls:
            with langfuse.start_as_current_span(
                name=f"Tool: {tool_call['name']}",
                input=tool_call["input"],
                metadata={
                    "tool_name": tool_call["name"],
                    "tool_id": tool_call["id"],
                },
            ) as tool_span:
                tool_span.update(output=tool_call["output"])
            debug(f"Created span for tool: {tool_call['name']}")

        # Update trace with final output
        trace_span.update(output={"role": "assistant", "content": final_output})

    debug(f"Created trace for turn {turn_num}")


def process_transcript(langfuse: Langfuse, session_id: str, transcript_file: Path, state: dict, project_name: str = "") -> int:
    """Process a transcript file and create traces for new turns.

    This function implements incremental processing:
    - Reads the state file to find where we left off
    - Processes only new messages since last run
    - Groups messages into turns (user -> assistant -> tools)
    - Creates a Langfuse trace for each complete turn
    - Updates state with new position

    Returns: Number of new turns processed
    """
    # Load session state
    session_state = state.get(session_id, {})
    last_line = session_state.get("last_line", 0)
    turn_count = session_state.get("turn_count", 0)

    # Read transcript file
    lines = transcript_file.read_text().strip().split("\n")
    total_lines = len(lines)

    # Check if there are new lines to process
    if last_line >= total_lines:
        debug(f"No new lines to process (last: {last_line}, total: {total_lines})")
        return 0

    # Parse new messages, tracking parse failures
    new_messages = []
    bad_line_count = 0
    last_valid_line = last_line
    for i in range(last_line, total_lines):
        try:
            msg = json.loads(lines[i])
            new_messages.append(msg)
            last_valid_line = i + 1
        except json.JSONDecodeError as e:
            bad_line_count += 1
            # If it's the very last line, it may be a partial write — don't advance past it
            if i == total_lines - 1:
                log("WARN", f"Skipping incomplete tail line {i + 1} in {transcript_file.name} (may be partial write)")
                last_valid_line = i  # Don't advance past this line
            else:
                log("WARN", f"Malformed JSONL at line {i + 1} in {transcript_file.name}: {e}")

    if bad_line_count > 0:
        log("INFO", f"Session {session_id}: {bad_line_count} malformed line(s) out of {total_lines - last_line} new")

    if not new_messages:
        return 0

    debug(f"Processing {len(new_messages)} new messages")

    # Group messages into turns
    # A turn is: user message -> assistant message(s) -> tool results
    turns = 0
    current_user = None
    current_assistants = []
    current_assistant_parts = []
    current_msg_id = None
    current_tool_results = []

    for msg in new_messages:
        role = msg.get("type") or (msg.get("message", {}).get("role"))

        if role == "user":
            # Check if this is a tool result (user messages containing tool_result blocks)
            if is_tool_result(msg):
                current_tool_results.append(msg)
                continue

            # Merge any pending assistant parts
            if current_msg_id and current_assistant_parts:
                merged = merge_assistant_parts(current_assistant_parts)
                current_assistants.append(merged)
                current_assistant_parts = []
                current_msg_id = None

            # If we have a complete turn, create a trace
            if current_user and current_assistants:
                turns += 1
                turn_num = turn_count + turns
                create_trace(langfuse, session_id, turn_num, current_user, current_assistants, current_tool_results, project_name)

            # Start new turn
            current_user = msg
            current_assistants = []
            current_assistant_parts = []
            current_msg_id = None
            current_tool_results = []

        elif role == "assistant":
            # Extract message ID to detect multi-part messages
            msg_id = None
            if isinstance(msg, dict) and "message" in msg:
                msg_id = msg["message"].get("id")

            if not msg_id:
                # No ID means single-part message
                current_assistant_parts.append(msg)
            elif msg_id == current_msg_id:
                # Same ID means continuation of current message
                current_assistant_parts.append(msg)
            else:
                # New ID means new assistant message
                if current_msg_id and current_assistant_parts:
                    merged = merge_assistant_parts(current_assistant_parts)
                    current_assistants.append(merged)

                current_msg_id = msg_id
                current_assistant_parts = [msg]

    # Handle final assistant message
    if current_msg_id and current_assistant_parts:
        merged = merge_assistant_parts(current_assistant_parts)
        current_assistants.append(merged)

    # Create trace for final turn if complete
    if current_user and current_assistants:
        turns += 1
        turn_num = turn_count + turns
        create_trace(langfuse, session_id, turn_num, current_user, current_assistants, current_tool_results, project_name)

    # Update state atomically
    state[session_id] = {
        "last_line": last_valid_line,
        "turn_count": turn_count + turns,
        "bad_line_count": session_state.get("bad_line_count", 0) + bad_line_count,
        "updated": datetime.now(timezone.utc).isoformat(),
    }
    save_state(state)

    return turns


def main():
    """Main entry point for the hook."""
    script_start = datetime.now()
    debug("Hook started")

    # Check if tracing is enabled
    if os.environ.get("TRACE_TO_LANGFUSE", "").lower() != "true":
        debug("Tracing disabled (TRACE_TO_LANGFUSE != true)")
        sys.exit(0)

    # Get Langfuse credentials from environment
    public_key = os.environ.get("LANGFUSE_PUBLIC_KEY")
    secret_key = os.environ.get("LANGFUSE_SECRET_KEY")
    host = os.environ.get("LANGFUSE_HOST", "http://localhost:3050")

    if not public_key or not secret_key:
        log("ERROR", "Langfuse API keys not set")
        sys.exit(0)

    # Initialize Langfuse client
    try:
        langfuse = Langfuse(
            public_key=public_key,
            secret_key=secret_key,
            host=host,
        )
    except Exception as e:
        log("ERROR", f"Failed to initialize Langfuse client: {e}")
        sys.exit(0)

    # Load state (with corruption recovery)
    state = load_state()

    # Find all active transcripts
    transcripts = find_all_transcripts()
    if not transcripts:
        debug("No transcript files found")
        sys.exit(0)

    log("INFO", f"Found {len(transcripts)} transcript(s) to process")

    # Process all transcripts incrementally
    total_turns = 0
    try:
        for session_id, transcript_file, project_name in transcripts:
            log("INFO", f"Processing session {session_id} ({project_name}) from {transcript_file.name}")
            turns = process_transcript(langfuse, session_id, transcript_file, state, project_name)
            total_turns += turns
            if turns > 0:
                session_state = state.get(session_id, {})
                log("INFO", f"  Emitted {turns} turn(s), cursor at line {session_state.get('last_line', '?')}, total turns: {session_state.get('turn_count', '?')}")

        langfuse.flush()
        duration = (datetime.now() - script_start).total_seconds()
        log("INFO", f"Done: {total_turns} turn(s) across {len(transcripts)} session(s) in {duration:.1f}s")

        # Warn if hook is taking too long
        if duration > 180:
            log("WARN", f"Hook took {duration:.1f}s (>3min), consider optimizing")

    except Exception as e:
        log("ERROR", f"Failed to process transcripts: {e}")
        import traceback
        debug(traceback.format_exc())
    finally:
        langfuse.shutdown()

    sys.exit(0)


if __name__ == "__main__":
    main()
