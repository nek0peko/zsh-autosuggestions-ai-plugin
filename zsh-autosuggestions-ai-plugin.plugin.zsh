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

_zsh_autosuggest_strategy_ai() {
	emulate -L zsh

	typeset -g suggestion=

	local buffer="$1"

	# Nothing to complete on an empty buffer.
	[[ -n "$buffer" ]] || return

	# Runtime dependency check: silently skip if the toolchain isn't
	# installed, so suggestions degrade gracefully to history-only.
	(( $+commands[ollama] )) || return
	(( $+commands[python3] )) || return

	# Debounce: if another key arrives within this window, the async
	# machinery kills this whole fork (including the sleep and the model
	# request) before we hit the model.
	command sleep "$ZSH_AUTOSUGGEST_AI_DEBOUNCE"

	# Recent commands as context (most recent last).
	local history_ctx
	history_ctx="$(fc -ln -$ZSH_AUTOSUGGEST_AI_HISTORY_SIZE -1 2>/dev/null)"

	# All request building / HTTP / parsing happens in one python call so
	# we never hand-roll JSON escaping in the shell. It prints the suffix
	# to append (no trailing newline) or nothing on any failure.
	local suffix
	suffix="$(
		ZSH_AUTOSUGGEST_AI_MODEL="$ZSH_AUTOSUGGEST_AI_MODEL" \
		ZSH_AUTOSUGGEST_AI_ENDPOINT="$ZSH_AUTOSUGGEST_AI_ENDPOINT" \
		python3 -c '
import json, os, sys, urllib.request

buffer = sys.argv[1]
history = sys.argv[2]
model = os.environ["ZSH_AUTOSUGGEST_AI_MODEL"]
endpoint = os.environ["ZSH_AUTOSUGGEST_AI_ENDPOINT"]

prompt = (
    "You are a shell command completion engine. Given a partial command, "
    "output ONLY the characters needed to complete the current (final) word. "
    "Never repeat the input. Output at most one word or flag, no spaces, no "
    "explanation, no quotes, no punctuation, no newlines. If nothing fits, "
    "output nothing.\n\n"
)
if history.strip():
    prompt += "Recent commands the user ran, newest last (context only):\n"
    prompt += history.strip() + "\n\n"
prompt += (
    "Partial: git pus\nMissing suffix: h\n"
    "Partial: git pu\nMissing suffix: ll\n"
    "Partial: ca\nMissing suffix: t\n"
    "Partial: docke\nMissing suffix: r\n"
    "Partial: git che\nMissing suffix: ckout\n"
    "Partial: " + buffer + "\nMissing suffix:"
)

body = json.dumps({
    "model": model,
    "prompt": prompt,
    "think": False,
    "stream": False,
    "options": {"temperature": 0, "num_predict": 20},
}).encode()

try:
    req = urllib.request.Request(
        endpoint, data=body, headers={"Content-Type": "application/json"})
    data = json.loads(urllib.request.urlopen(req, timeout=10).read())
except Exception:
    sys.exit(0)

resp = data.get("response", "")
# Keep only the first line, trim, and enforce the single-token limit.
suffix = resp.splitlines()[0].strip() if resp else ""
suffix = suffix.split()[0] if suffix.split() else ""
sys.stdout.write(suffix)
' "$buffer" "$history_ctx" 2>/dev/null
	)"

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
