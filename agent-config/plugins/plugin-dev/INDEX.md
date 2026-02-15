# Plugin-Dev: Complete Index

Welcome to the plugin-dev toolkit! This is your comprehensive guide to building Claude Code plugins.

## Quick Navigation

- **[README.md](README.md)** - Main overview and getting started
- **[DOWNLOAD_SUMMARY.txt](DOWNLOAD_SUMMARY.txt)** - Complete download statistics and verification
- **[DOWNLOAD_MANIFEST.md](DOWNLOAD_MANIFEST.md)** - Detailed file-by-file manifest

## What is Plugin-Dev?

The plugin-dev toolkit is a comprehensive resource for building Claude Code plugins. It includes:

- **3 Autonomous Agents** - AI-powered tools for creating, validating, and reviewing plugin components
- **1 Guided Command** - An 8-phase structured workflow for building plugins from scratch
- **7 Specialized Skills** - Expert guidance on all aspects of plugin development

## Getting Started

### Option 1: Use the Guided Workflow (Recommended)
```bash
/plugin-dev:create-plugin
```

This launches the comprehensive 8-phase workflow:
1. **Discovery** - Define your plugin's purpose
2. **Component Planning** - Identify needed pieces
3. **Detailed Design** - Resolve specifications
4. **Structure Creation** - Set up directories
5. **Implementation** - Build each component
6. **Validation** - Check quality
7. **Testing** - Verify functionality
8. **Documentation** - Prepare for distribution

### Option 2: Use Specific Agents

- **agent-creator** - Generate autonomous agents
  ```bash
  Use the agent-creator agent to build my data processor
  ```

- **plugin-validator** - Check plugin structure
  ```bash
  Use the plugin-validator agent to validate my plugin
  ```

- **skill-reviewer** - Review skill quality
  ```bash
  Use the skill-reviewer agent to review my skill
  ```

### Option 3: Learn from Skills Directly

Each skill provides comprehensive guidance with examples and references:

1. **Hook Development** - Event-driven automation
   - Learn event hooks for automation
   - See working examples
   - Understand security best practices

2. **MCP Integration** - External service integration
   - Configure Model Context Protocol servers
   - Connect databases, APIs, and tools
   - Examples: stdio, SSE, HTTP, WebSocket

3. **Plugin Structure** - Organization patterns
   - Understand plugin directory layout
   - Auto-discovery mechanisms
   - Manifest configuration

4. **Plugin Settings** - Configuration management
   - User-configurable settings patterns
   - YAML frontmatter configuration
   - Real-world examples

5. **Command Development** - Creating slash commands
   - Markdown-based command syntax
   - Frontmatter configuration
   - Dynamic arguments and workflows

6. **Agent Development** - Building autonomous agents
   - Agent configuration and triggers
   - System prompt design
   - Tool access and permissions

7. **Skill Development** - Creating reusable skills
   - Progressive disclosure pattern
   - Skill structure and metadata
   - Trigger phrases and examples

## Directory Structure

```
plugin-dev/
├── README.md                           Main documentation
├── plugin.json                         Plugin manifest (root level)
│
├── agents/                             Autonomous agents
│   ├── agent-creator.md               AI agent code generator
│   ├── plugin-validator.md            Plugin structure validator
│   └── skill-reviewer.md              Skill quality reviewer
│
├── commands/                           Workflow commands
│   └── create-plugin.md               8-phase plugin creation
│
└── skills/                             Development guides
    ├── hook-development/              Event hooks & automation
    ├── mcp-integration/               External service integration
    ├── plugin-structure/              Directory & manifest patterns
    ├── plugin-settings/               Configuration patterns
    ├── command-development/           Slash command creation
    ├── agent-development/             Agent creation guide
    └── skill-development/             Skill creation guide
```

## Key Concepts

### Progressive Disclosure
Each skill follows a structured pattern:
- **SKILL.md** - Core 1,500-2,000 word guide (always loaded)
- **examples/** - 2-3 working implementation examples
- **references/** - 2-7 detailed reference documents
- **scripts/** - Validation and utility scripts

This keeps your context focused while providing comprehensive information when needed.

### Component Auto-Discovery
Claude Code automatically discovers:
- Commands in `commands/` directory
- Agents in `agents/` directory
- Skills in `skills/` directory with `SKILL.md` files
- Hooks in `hooks/` directory
- MCP servers in `.mcp.json` or `plugin.json`

### Portable Paths
Always use `${CLAUDE_PLUGIN_ROOT}` for file references to work across different installation methods.

## Common Workflows

### Build a Complete Plugin
1. Start with `/plugin-dev:create-plugin`
2. Answer discovery questions about your plugin's purpose
3. Let the workflow guide you through each phase
4. Run validation at each step
5. Test in Claude Code

### Create an Agent
Ask the agent-creator:
```
Create an agent that analyzes code for security vulnerabilities
```

### Add a Command
Use command-development skill:
```
I need to create a command that builds and deploys my application
```

### Configure MCP Integration
Learn from mcp-integration skill:
```
How do I connect to my database using MCP?
```

### Set Up Plugin Settings
Use plugin-settings skill:
```
How do I let users configure my plugin?
```

## Validation Tools

Production-ready scripts included:

**Hook Validation**
- `validate-hook-schema.sh` - Validate hook configuration
- `test-hook.sh` - Test hook execution
- `hook-linter.sh` - Lint hook scripts

**Agent Validation**
- `validate-agent.sh` - Verify agent configuration

**Settings Validation**
- `parse-frontmatter.sh` - Parse YAML frontmatter
- `validate-settings.sh` - Validate settings files

## Examples Included

### Hook Examples
- **load-context.sh** - Load project context on session start
- **validate-bash.sh** - Validate bash commands before execution
- **validate-write.sh** - Validate file write operations

### MCP Configuration Examples
- **stdio-server.json** - Local process server
- **sse-server.json** - Hosted service with OAuth
- **http-server.json** - REST API integration

### Plugin Structure Examples
- **minimal-plugin.md** - Bare minimum plugin
- **standard-plugin.md** - Typical plugin layout
- **advanced-plugin.md** - Feature-rich plugin

### Command Examples
- **simple-commands.md** - Basic command patterns
- **plugin-commands.md** - Plugin-specific commands

### Agent Examples
- **agent-creation-prompt.md** - How to describe agents
- **complete-agent-examples.md** - Full working agents

## Best Practices

✓ **Do:**
- Use the guided workflow for best structure
- Validate your plugin before publishing
- Follow naming conventions (lowercase, hyphens)
- Test in Claude Code before distribution
- Document your plugin thoroughly
- Use `${CLAUDE_PLUGIN_ROOT}` for paths
- Input validation in hooks
- Minimal tool access for agents

✗ **Don't:**
- Hardcode paths (use environment variables)
- Skip validation steps
- Store credentials in code
- Use generic hook names
- Overlapping hook configurations
- Skip testing on actual Claude Code

## Getting Help

Each skill includes:
- **Core documentation** - Quick reference guide
- **Working examples** - Functional code samples
- **Reference docs** - Detailed specifications
- **Utility scripts** - Automated validation

Use relevant agent triggers to get AI assistance:
- "Create an agent that..."
- "Validate my plugin"
- "Review my skill"
- "How do I implement..."

## File Reference

| File | Purpose | Type |
|------|---------|------|
| README.md | Overview and features | Documentation |
| plugin.json | Plugin manifest | Configuration |
| agents/*.md | Autonomous agents | Markdown + YAML |
| commands/*.md | Workflow commands | Markdown + YAML |
| skills/*/SKILL.md | Skill core guides | Markdown + YAML |
| skills/*/examples/ | Working samples | Markdown/Shell/JSON |
| skills/*/references/ | Detailed docs | Markdown |
| skills/*/scripts/ | Utilities | Shell scripts |

## Statistics

- **61 Total Files** downloaded from GitHub
- **46 Markdown** documentation files
- **10 Shell** validation scripts
- **5 JSON** configuration files
- **~11,000+ words** of core documentation
- **12+ working** examples
- **7 comprehensive** skills
- **3 powerful** agents
- **1 guided** workflow command

## Updates & Support

This plugin is maintained as part of Claude Code. For updates, questions, or issues:
- GitHub: https://github.com/anthropics/claude-code
- Plugin: `plugins/plugin-dev/`

---

**Ready to build?** Start with `/plugin-dev:create-plugin` or ask one of the agents!
