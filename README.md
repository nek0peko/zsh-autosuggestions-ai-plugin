# zsh-autosuggestions-ai-plugin

A local-LLM fallback strategy for
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions).
When `history` has no match, it asks a local model (via
[Ollama](https://ollama.com)) to complete the command you're typing. It plugs
in through the official `ZSH_AUTOSUGGEST_STRATEGY` mechanism, so
zsh-autosuggestions stays completely unmodified.

Only `curl` is required at runtime. If Ollama or `curl` is missing, the
strategy silently does nothing and suggestions fall back to history only.

## Install

1. Install [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
   and [Ollama](https://ollama.com/download), then pull the model:

   ```sh
   ollama pull qwen3.5:4b
   ```

2. Clone this repo:

   ```sh
   git clone https://github.com/nek0peko/zsh-autosuggestions-ai-plugin ~/.zsh/zsh-autosuggestions-ai-plugin
   ```

3. Load it **after** zsh-autosuggestions in `~/.zshrc`.

   If you installed zsh-autosuggestions via Homebrew, add:

   ```sh
   source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
   source ~/.zsh/zsh-autosuggestions-ai-plugin/zsh-autosuggestions-ai-plugin.plugin.zsh
   ```

   Oh My Zsh users instead clone into the custom plugins dir and add both to
   your `plugins=(...)` list, with this plugin **after** `zsh-autosuggestions`:

   ```sh
   git clone https://github.com/nek0peko/zsh-autosuggestions-ai-plugin "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions-ai-plugin"
   ```

   ```sh
   plugins=(... zsh-autosuggestions zsh-autosuggestions-ai-plugin)
   ```

4. Start a new terminal (or run `exec zsh`).

> **Order matters:** source the official plugin first. This plugin
> auto-appends `ai` to `ZSH_AUTOSUGGEST_STRATEGY` only if zsh-autosuggestions
> is already loaded.

## Usage

Just type. `history` serves commands you've run before (instant); for anything
new, the `ai` strategy kicks in after a short debounce and the local model
suggests a completion. Accept it with <kbd>→</kbd> like any suggestion.

Override behavior by setting these before sourcing the plugin:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ZSH_AUTOSUGGEST_AI_MODEL` | `qwen3.5:4b` | Ollama model tag |
| `ZSH_AUTOSUGGEST_AI_DEBOUNCE` | `0.2` | Debounce seconds before calling the model |
| `ZSH_AUTOSUGGEST_AI_ENDPOINT` | `http://localhost:11434/api/generate` | Ollama endpoint |
| `ZSH_AUTOSUGGEST_AI_PROMPT_FILE` | `<plugin dir>/prompt.txt` | Prompt template; `{INPUT}` is replaced with the buffer |

To control strategy order yourself (it won't duplicate `ai`):

```sh
ZSH_AUTOSUGGEST_STRATEGY=(history completion ai)
```

## License

[MIT](LICENSE) © nek0peko
