#--------------------------------------------------------------------#
# zsh-autosuggestions-ai-plugin                                      #
#--------------------------------------------------------------------#
# A drop-in AI suggestion strategy for zsh-autosuggestions, backed by
# a local LLM served by Ollama. It plugs into the official
# zsh-autosuggestions via its public ZSH_AUTOSUGGEST_STRATEGY mechanism
# -- this plugin does NOT modify or vendor zsh-autosuggestions at all.
#
# How it works:
#   zsh-autosuggestions tries each entry in ZSH_AUTOSUGGEST_STRATEGY in
#   order and uses the first non-empty result. This plugin registers an
#   `ai` strategy that is consulted only when earlier strategies (e.g.
#   `history`) find no match, so your normal typing stays instant and
#   the model is called only as a fallback.
#
# Debounce + interruption come for free from zsh-autosuggestions' async
# machinery: every keystroke forks a fresh subprocess to fetch a
# suggestion and kills the previous fork's process group. We run inside
# that fork, so:
#   * `sleep $ZSH_AUTOSUGGEST_AI_DEBOUNCE` at the top acts as a debounce
#     -- keep typing and this fork is killed before the model is called.
#   * killing the fork's process group also cancels the in-flight model
#     request, so a pending suggestion stops the moment you press a key.
#
# Implementation is intentionally dependency-light: only `curl` is used
# to talk to Ollama (no python/jq), and JSON is built/parsed with pure
# zsh parameter expansion.
#
# Model is hardwired to qwen3.5:4b for now; the variables below are
# exposed with defaults so making it configurable later is trivial.

# Model pinned for now; override only if you know what you're doing.
: ${ZSH_AUTOSUGGEST_AI_MODEL:=qwen3.5:4b}
# Debounce window (seconds). Paid only when the AI fallback actually runs.
: ${ZSH_AUTOSUGGEST_AI_DEBOUNCE:=0.2}
# How many recent commands to feed the model as context.
: ${ZSH_AUTOSUGGEST_AI_HISTORY_SIZE:=20}
# Ollama HTTP endpoint.
: ${ZSH_AUTOSUGGEST_AI_ENDPOINT:=http://localhost:11434/api/generate}

# Escape a string for embedding inside a JSON string literal.
_zsh_autosuggest_ai_json_escape() {
	local s=$1
	s=${s//\\/\\\\}      # backslash first
	s=${s//\"/\\\"}      # double quote
	s=${s//$'\n'/\\n}    # newline
	s=${s//$'\r'/\\r}    # carriage return
	s=${s//$'\t'/\\t}    # tab
	print -rn -- "$s"
}

_zsh_autosuggest_strategy_ai() {
	emulate -L zsh

	typeset -g suggestion=

	local buffer="$1"

	# Nothing to complete on an empty buffer.
	[[ -n "$buffer" ]] || return

	# Runtime dependency check: silently skip if curl isn't installed, so
	# suggestions degrade gracefully to history-only.
	(( $+commands[curl] )) || return

	# Debounce: if another key arrives within this window, the async
	# machinery kills this whole fork (including the sleep and the model
	# request) before we hit the model.
	command sleep "$ZSH_AUTOSUGGEST_AI_DEBOUNCE"

	# Recent commands as context (most recent last).
	local history_ctx
	history_ctx="$(fc -ln -$ZSH_AUTOSUGGEST_AI_HISTORY_SIZE -1 2>/dev/null)"

	# Build the prompt (plain text), then JSON-escape the whole thing.
	local prompt
	prompt="You are a shell command completion engine. Given a partial command, output ONLY the characters needed to complete the current (final) word. Never repeat the input. Output at most one word or flag, no spaces, no explanation, no quotes, no punctuation, no newlines. If nothing fits, output nothing."$'\n\n'
	if [[ -n "${history_ctx//[[:space:]]/}" ]]; then
		prompt+="Recent commands the user ran, newest last (context only):"$'\n'"$history_ctx"$'\n\n'
	fi
	prompt+="Partial: git pus"$'\n'"Missing suffix: h"$'\n'
	prompt+="Partial: git pu"$'\n'"Missing suffix: ll"$'\n'
	prompt+="Partial: ca"$'\n'"Missing suffix: t"$'\n'
	prompt+="Partial: docke"$'\n'"Missing suffix: r"$'\n'
	prompt+="Partial: git che"$'\n'"Missing suffix: ckout"$'\n'
	prompt+="Partial: $buffer"$'\n'"Missing suffix:"

	local prompt_json model_json
	prompt_json="$(_zsh_autosuggest_ai_json_escape "$prompt")"
	model_json="$(_zsh_autosuggest_ai_json_escape "$ZSH_AUTOSUGGEST_AI_MODEL")"

	# One curl call to Ollama. Non-streaming response is a single JSON
	# object whose "response" field holds the model output.
	local resp
	resp="$(curl -s --max-time 10 "$ZSH_AUTOSUGGEST_AI_ENDPOINT" \
		-H 'Content-Type: application/json' \
		-d "{\"model\":\"$model_json\",\"prompt\":\"$prompt_json\",\"think\":false,\"stream\":false,\"options\":{\"temperature\":0,\"num_predict\":20}}" \
		2>/dev/null)" || return

	# Extract the "response" field value from the JSON (it is the last
	# such key; the model output never contains an unescaped quote for our
	# single-token prompt, so a simple slice is safe).
	[[ "$resp" == *'"response":"'* ]] || return
	local suffix="${resp#*\"response\":\"}"
	suffix="${suffix%%\"*}"

	# Unescape the few sequences our escape step could have produced, then
	# keep only the first line and first whitespace-delimited token.
	suffix="${suffix//\\n/ }"
	suffix="${suffix//\\t/ }"
	suffix="${suffix//\\\"/\"}"
	suffix="${suffix//\\\\/\\}"
	suffix="${suffix%%[[:space:]]*}"

	# zsh-autosuggestions expects the full command line (prefix + suffix),
	# and only keeps it if it starts with buffer.
	[[ -n "$suffix" ]] && suggestion="${buffer}${suffix}"
}

# Auto-register the `ai` strategy as a fallback after `history`, but only
# if zsh-autosuggestions is loaded and the user hasn't already placed
# `ai` in the list themselves. This is the single line of "wiring" and
# it is fully overridable from your .zshrc.
if (( $+functions[_zsh_autosuggest_bind_widgets] )); then
	if [[ -z "${ZSH_AUTOSUGGEST_STRATEGY[(r)ai]}" ]]; then
		typeset -ga ZSH_AUTOSUGGEST_STRATEGY
		ZSH_AUTOSUGGEST_STRATEGY+=(ai)
	fi
fi
