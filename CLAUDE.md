# No More Configs — Workspace

## Projects

User projects live in `projects/`. When a user asks to create, clone, or set up a new project, place it at `projects/<project-name>/`.

```bash
cd /workspace/projects
git clone <url>
# or
mkdir my-project && cd my-project
```

After adding a project, remind the user to add it to `config.json → vscode.git_scan_paths` so VS Code's git scanner picks it up:

```json
{ "vscode": { "git_scan_paths": ["projects/my-project"] } }
```

## Next.js Projects

Fast refresh does not work in Docker without two changes:

**`package.json`** — dev script must use `--webpack`:

```json
{ "scripts": { "dev": "next dev --webpack" } }
```

**`next.config.ts`** — add polling to webpack watch options:

```ts
const nextConfig: NextConfig = {
  webpack: (config) => {
    config.watchOptions = {
      poll: 1000,
      aggregateTimeout: 300,
    };
    return config;
  },
};
```

Apply both whenever creating or modifying a Next.js project in this workspace.
