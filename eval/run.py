#!/usr/bin/env python3
"""
Prompt evaluation harness for zsh-autosuggestions-ai-plugin.

Usage:
    python3 run.py                                    # default prompt.txt + qwen3.5:4b
    python3 run.py --prompt prompt_v2.txt
    python3 run.py --model qwen3.5:4b-mlx -v
    python3 run.py --cases 5,8,19                     # only run selected cases

Testset format (eval/testset.jsonl, one JSON object per line):
    {"input": "git pu", "expected": ["ll", "sh"], "note": "..."}

A case passes if the model's trimmed first token equals ANY string in `expected`.
"""
import argparse
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).parent
REPO = ROOT.parent


def load_cases(path: pathlib.Path) -> list[dict]:
    cases = []
    for i, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            cases.append(json.loads(line))
        except json.JSONDecodeError as e:
            sys.exit(f"testset.jsonl line {i}: {e}")
    return cases


def call_ollama(endpoint: str, model: str, prompt: str, timeout: float = 15) -> tuple[str, float]:
    body = json.dumps({
        "model": model,
        "prompt": prompt,
        "think": False,
        "stream": False,
        "options": {
            "temperature": 0,
            "num_predict": 24,
            "stop": ["\n", "Input:", "input:", "->"],
        },
    }).encode()
    req = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read())
    return data.get("response", ""), (time.perf_counter() - t0) * 1000


def normalize(raw: str, input_text: str = "") -> str:
    """Mirror the plugin: strip, take first line, first whitespace token."""
    s = raw.replace("\r", "")
    if "\n" in s:
        s = s.split("\n", 1)[0]
    s = s.strip()
    if not s or s == "<EMPTY>":
        return ""
    # keep first whitespace-delimited token
    for sep in (" ", "\t"):
        if sep in s:
            s = s.split(sep, 1)[0]
    # the model sometimes re-emits the input prefix; strip it if present
    if input_text and s.startswith(input_text):
        s = s[len(input_text):]
    return s


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", default=str(ROOT / "prompt.txt"))
    ap.add_argument("--testset", default=str(REPO / "eval.jsonl"))
    ap.add_argument("--model", default="qwen3.5:4b")
    ap.add_argument("--endpoint", default="http://localhost:11434/api/generate")
    ap.add_argument("--cases", help="comma-separated 1-based indices to run (default: all)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print the model's raw output too")
    args = ap.parse_args()

    tmpl = pathlib.Path(args.prompt).read_text()
    if "{INPUT}" not in tmpl:
        sys.exit(f"prompt file {args.prompt} must contain the placeholder {{INPUT}}")
    cases = load_cases(pathlib.Path(args.testset))

    if args.cases:
        want = {int(x) for x in args.cases.split(",") if x.strip()}
        cases = [c for i, c in enumerate(cases, 1) if i in want]

    passed = 0
    latencies = []
    by_cat: dict[str, list[int]] = {}
    print(f"model={args.model}  prompt={args.prompt}  cases={len(cases)}")
    print("-" * 72)
    for i, case in enumerate(cases, 1):
        prompt = tmpl.replace("{INPUT}", case["input"])
        try:
            raw, ms = call_ollama(args.endpoint, args.model, prompt)
        except Exception as e:
            print(f"[{i:3d}] {case['input']!r:40} ERROR: {e}")
            continue
        latencies.append(ms)
        out = normalize(raw, case["input"])
        expected = case["expected"]
        ok = out in expected if expected else out == ""
        passed += ok
        cat = case.get("category", "?")
        by_cat.setdefault(cat, [0, 0])
        by_cat[cat][1] += 1
        by_cat[cat][0] += int(ok)
        mark = "✓" if ok else "✗"
        exp_str = "/".join(repr(e) for e in expected) if expected else "<empty>"
        suffix = f"  raw={raw!r}" if args.verbose else ""
        print(f"[{i:3d}] {mark} [{cat:7}] {case['input']!r:38} → {out!r:16} want {exp_str}{suffix}  {ms:.0f}ms")
    print("-" * 72)
    avg = sum(latencies) / len(latencies) if latencies else 0
    p95 = sorted(latencies)[int(len(latencies) * 0.95) - 1] if latencies else 0
    print(f"passed {passed}/{len(cases)}  ({100*passed/max(len(cases),1):.1f}%)  avg {avg:.0f}ms  p95 {p95:.0f}ms")
    for cat, (p, t) in sorted(by_cat.items()):
        print(f"  {cat:8} {p:3d}/{t:3d}  ({100*p/t:.0f}%)")
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main())
