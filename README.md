# zsh-autosuggestions-ai-plugin

A drop-in **AI suggestion strategy** for
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions),
backed by a **local LLM** served by [Ollama](https://ollama.com).

It plugs into the official plugin through its public
`ZSH_AUTOSUGGEST_STRATEGY` mechanism — it does **not** modify or vendor
zsh-autosuggestions. You keep upstream exactly as-is and just add this
small plugin on top.

## How it works

zsh-autosuggestions tries each entry in `ZSH_AUTOSUGGEST_STRATEGY` in order
and uses the first non-empty result. This plugin registers an `ai` strategy
that is consulted **only when earlier strategies (e.g. `history`) find no
match**. So:

- Your normal typing stays instant (served by `history`).
- The local model is called only as a fallback for commands you've never run.
- **Debounce + interruption are free**: zsh-autosuggestions forks a fresh
  subprocess per keystroke and kills the previous one, so typing another key
  both debounces (we `sleep` before calling the model) and cancels any
  in-flight request.

## Requirements

- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- [Ollama](https://ollama.com) + the model (see [INSTALL.md](INSTALL.md))
- `python3` (used to talk to the Ollama HTTP API)

If Ollama or python3 isn't installed, the strategy silently does nothing and
suggestions fall back to history only.

## Installation

See [INSTALL.md](INSTALL.md). Short version:

```sh
# 1. official plugin (unchanged)
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
# 2. this plugin (auto-appends `ai` as a fallback strategy)
source ~/.zsh/zsh-autosuggestions-ai-plugin/zsh-autosuggestions-ai-plugin.plugin.zsh
```

> **Order matters:** source the official plugin *first*, then this one. The
> `ai` strategy relies on zsh-autosuggestions' async machinery, and this
> plugin auto-registers `ai` only if zsh-autosuggestions is already loaded.

## Configuration

The model is hardwired to `qwen3.5:4b` for now. These variables are exposed
with defaults if you want to tweak behavior; set them before sourcing:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ZSH_AUTOSUGGEST_AI_MODEL` | `qwen3.5:4b` | Ollama model tag |
| `ZSH_AUTOSUGGEST_AI_DEBOUNCE` | `0.2` | Debounce seconds before calling the model |
| `ZSH_AUTOSUGGEST_AI_HISTORY_SIZE` | `20` | Recent commands fed as context |
| `ZSH_AUTOSUGGEST_AI_ENDPOINT` | `http://localhost:11434/api/generate` | Ollama endpoint |

To control strategy order yourself, set it explicitly before sourcing this
plugin (it won't duplicate `ai` if you've already added it):

```sh
ZSH_AUTOSUGGEST_STRATEGY=(history completion ai)
```

## License

[MIT](LICENSE) © nek0peko
