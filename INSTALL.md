# Installation

* [Prerequisites](#prerequisites)
* [Oh My Zsh](#oh-my-zsh)
* [Manual](#manual-git-clone)

This plugin extends [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions),
so you need that installed first. It adds a local-LLM fallback strategy; it
does not replace or modify the official plugin.

## Prerequisites

1. Install [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
   (via its own instructions).

2. Install Ollama: https://ollama.com/download

3. Pull the model (currently hardwired to `qwen3.5:4b`):

    ```sh
    ollama pull qwen3.5:4b
    ```

`python3` is also required (used to talk to the Ollama HTTP API). If Ollama or
python3 is missing, the plugin degrades gracefully to history-only suggestions.

## Oh My Zsh

1. Clone this repository into `$ZSH_CUSTOM/plugins` (by default `~/.oh-my-zsh/custom/plugins`)

    ```sh
    git clone https://github.com/nek0peko/zsh-autosuggestions-ai-plugin ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions-ai-plugin
    ```

2. Add the plugin to the list of plugins for Oh My Zsh to load (inside `~/.zshrc`),
   **after** `zsh-autosuggestions`:

    ```sh
    plugins=( 
        # other plugins...
        zsh-autosuggestions
        zsh-autosuggestions-ai-plugin
    )
    ```

3. Start a new terminal session.

## Manual (Git Clone)

1. Clone this repository somewhere on your machine. This guide will assume `~/.zsh/zsh-autosuggestions-ai-plugin`.

    ```sh
    git clone https://github.com/nek0peko/zsh-autosuggestions-ai-plugin ~/.zsh/zsh-autosuggestions-ai-plugin
    ```

2. Add the following to your `.zshrc`, **after** you source zsh-autosuggestions:

    ```sh
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
    source ~/.zsh/zsh-autosuggestions-ai-plugin/zsh-autosuggestions-ai-plugin.plugin.zsh
    ```

3. Start a new terminal session.
