# Airplane Mode

Set up offline coding on macOS with Ollama, a local Qwen model, and OpenCode v2.
The default is the exact `qwen3.8:27b-q4_K_M` tag. `qwen3-coder:30b` remains an
optional alternative.

## Set up while online

```bash
git clone https://github.com/daniilrrr/airplane-mode.git
cd airplane-mode
bash src/airplane-mode.sh
```

Setup installs missing tools, downloads the selected model if needed, tests a
local response, and adds an `airplane-mode` function to your shell profile.
Existing tools stay installed unless you explicitly update them. It backs up
changed profiles and preserves unrelated content. Run the `source` command
printed by setup. From the repository you want to work on, launch:

```bash
airplane-mode
# Use an alternative you already downloaded:
airplane-mode qwen3-coder:30b
```

Normal launches check for the local model and never pull models or update tools.
OpenCode receives session configuration without rewriting your existing settings.
Before travelling, turn Wi-Fi off and complete a real coding task in a local
repository. Remote tools, plugins, and network-dependent project commands can
still require connectivity.

## Update tools while online

```bash
bash src/airplane-mode.sh --update
# For an existing llama.cpp installation:
bash src/airplane-mode.sh --engine llama.cpp --update
```

This updates existing OpenCode and the selected engine with their detected
installation manager, then exits. It does not download models or change your
profile. Homebrew upgrades target only those packages. Unknown installation
managers require a manual update. See the [guide](GUIDE.md) for supported paths.

## Requirements and limits

Use macOS with Apple Silicon and enough free disk and unified memory for your
model, context, and other applications. The defaults target a 36 GB Mac and use
64,000 tokens of context, flash attention, and a `q8_0` cache. Memory use depends
on the model and workload. Check `ollama ps` during a real session rather than
assuming the model fits.

The launcher binds new Ollama servers to `127.0.0.1:11434` with cloud features
disabled. It reuses existing servers without restarting them. Restart an existing
server yourself to apply changed server settings.

OpenCode can read and write files and execute commands with your permissions.
Review its actions and any plugins you add. Setup installs no extra plugins,
MCP servers, or skills. Follow your organization's policy for sensitive code.

For the optional llama.cpp engine, run `bash src/airplane-mode.sh --engine llama.cpp`.
To change its model, rerun setup, source the updated profile, and stop the old server yourself before launching.
See [GUIDE.md](GUIDE.md) for model preparation and troubleshooting.

## License

MIT
