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

# Model pinned for now; override only if you know what you're doing.
: ${ZSH_AUTOSUGGEST_AI_MODEL:=qwen3.5:4b}
# Debounce window (seconds). Paid only when the AI fallback actually runs.
: ${ZSH_AUTOSUGGEST_AI_DEBOUNCE:=0.2}
# Ollama HTTP endpoint.
: ${ZSH_AUTOSUGGEST_AI_ENDPOINT:=http://localhost:11434/api/generate}
# Path to the prompt template; `{INPUT}` is replaced with the user's buffer.
: ${ZSH_AUTOSUGGEST_AI_PROMPT_FILE:=${0:A:h}/prompt.txt}

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

	# Prompt template must exist on disk.
	[[ -r "$ZSH_AUTOSUGGEST_AI_PROMPT_FILE" ]] || return

	# Debounce: if another key arrives within this window, the async
	# machinery kills this whole fork (including the sleep and the model
	# request) before we hit the model.
	command sleep "$ZSH_AUTOSUGGEST_AI_DEBOUNCE"

	# Load the prompt template and substitute the user's buffer.
	local template prompt
	template="$(<"$ZSH_AUTOSUGGEST_AI_PROMPT_FILE")"
	prompt="${template//\{INPUT\}/$buffer}"

	local prompt_json model_json
	prompt_json="$(_zsh_autosuggest_ai_json_escape "$prompt")"
	model_json="$(_zsh_autosuggest_ai_json_escape "$ZSH_AUTOSUGGEST_AI_MODEL")"

	# One curl call to Ollama. Non-streaming response is a single JSON
	# object whose "response" field holds the model output.
	local resp
	resp="$(curl -s --max-time 10 "$ZSH_AUTOSUGGEST_AI_ENDPOINT" \
		-H 'Content-Type: application/json' \
		-d "{\"model\":\"$model_json\",\"prompt\":\"$prompt_json\",\"think\":false,\"stream\":false,\"options\":{\"temperature\":0,\"num_predict\":24,\"stop\":[\"\\n\",\"Input:\",\"input:\",\"->\"]}}" \
		2>/dev/null)" || return

	# Extract the "response" field value from the JSON.
	[[ "$resp" == *'"response":"'* ]] || return
	local suffix="${resp#*\"response\":\"}"
	suffix="${suffix%%\"*}"

	# Unescape the few sequences our escape step could have produced, then
	# keep only the first line and strip leading/trailing whitespace.
	suffix="${suffix//\\n/ }"
	suffix="${suffix//\\t/ }"
	suffix="${suffix//\\\"/\"}"
	suffix="${suffix//\\\\/\\}"
	suffix="${suffix%% *}"
	suffix="${suffix##[[:space:]]##}"
	suffix="${suffix%%[[:space:]]##}"

	# The prompt uses `<EMPTY>` as the "no suggestion" sentinel.
	[[ "$suffix" == "<EMPTY>" ]] && return

	# The model occasionally re-emits the user's input prefix; strip it.
	[[ -n "$suffix" && "$suffix" == "$buffer"* ]] && suffix="${suffix#$buffer}"

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
