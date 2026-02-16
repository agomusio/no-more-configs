---
name: gitprojects
description: Project directory mapping for repositories in the sandbox. Use when the user mentions a project by name, references gitprojects, asks about repos in the sandbox, or wants to work on a specific project.
license: MIT
metadata:
  author: Sam Boland
  version: "2.0.0"
---

# Git Projects Directory

All repositories developed inside the sandbox live under `/workspace/gitprojects/`. This skill maps project names to their paths so Claude Code can find them immediately.

## Project Registry

| Project Name | Directory | Remote | Status |
|-------------|-----------|--------|--------|

## Adding a New Project

1. Clone into `/workspace/gitprojects/`:
   ```bash
   cd /workspace/gitprojects && git clone <url>
   ```
2. Add the path to `config.json → vscode.git_scan_paths` for VS Code git integration
3. Rebuild the container (or manually add to `.vscode/settings.json`)
4. Update this skill file with the new project entry
