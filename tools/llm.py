"""Minimal OpenAI-compatible chat client using the keys from the user's opencode config
(~/.local/share/opencode/auth.json + baseURL in ~/.config/opencode/opencode.json). Never prints keys."""
import base64, json, os, re, time, urllib.request

def _cfg(provider):
    auth = json.load(open(os.path.expanduser("~/.local/share/opencode/auth.json")))
    txt = open(os.path.expanduser("~/.config/opencode/opencode.json")).read()
    m = re.search(r'"%s"\s*:\s*\{.*?"baseURL"\s*:\s*"([^"]+)"' % re.escape(provider), txt, re.S)
    return auth[provider]["key"], m.group(1).rstrip("/")

def chat(provider, model, messages, max_tokens=400, timeout=120, retries=3):
    key, base = _cfg(provider)
    body = json.dumps({"model": model, "messages": messages, "max_tokens": max_tokens, "temperature": 0.7}).encode()
    for i in range(retries):
        try:
            req = urllib.request.Request(base + "/chat/completions", body,
                                         {"Authorization": "Bearer " + key, "Content-Type": "application/json", "User-Agent": "opencode/1.18.19"})
            r = json.load(urllib.request.urlopen(req, timeout=timeout))
            c = r["choices"][0]["message"].get("content") or ""
            if not c.strip():
                raise RuntimeError("empty reply (token limit used up by reasoning?)")
            return c
        except Exception as e:
            err = str(e)[:200]
            time.sleep(2 * (i + 1))
    raise RuntimeError("llm failed: " + err)

def image_part(path):
    return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()}}
