"""Thin REST clients for the two LLM backends used by the modernization pipeline."""

import os
import threading
import time

import requests


# Azure OpenAI resource details. This resource (sureshopenaichat) uses the
# classic deployment-based REST shape --
# {endpoint}/openai/deployments/{deployment}/chat/completions?api-version=...
# -- NOT the v1 path (no deployment name in the URL, no api-version param)
# that a previous, now-expired resource used. Don't "simplify" this back to
# a v1 base_url without re-verifying against a live call first.
AZURE_ENDPOINT = "https://sureshopenaichat.services.ai.azure.com"
AZURE_API_VERSION = "2024-12-01-preview"
AZURE_DEFAULT_MODEL = "gpt-5.4-mini"

# Only models CONFIRMED as real, callable deployments on this Azure resource
# (verified via a direct API call returning a genuine completion, not just
# assumed from a catalog/model list).
AVAILABLE_AZURE_MODELS = [
    {"id": "gpt-5.4-mini", "label": "GPT-5.4 Mini (Azure OpenAI)"},
]

GEMINI_MODEL = "gemini-3.1-flash-lite"
GEMINI_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/"
    f"{GEMINI_MODEL}:generateContent"
)

# gpt-5.6-sol is a reasoning model: max_completion_tokens covers BOTH its
# invisible reasoning tokens AND its visible output. On a large/complex COBOL
# program it can burn the entire budget on reasoning and return empty content
# with finish_reason="length" -- a fixed cap that works for a 300-line file
# will silently fail on a 3000-line one. Detect that signature and escalate.
MAX_TOKEN_ESCALATIONS = 3
TOKEN_ESCALATION_CEILING = 64_000

# Transient network failures (e.g. ConnectionAbortedError WinError 10053,
# seen when many outbound HTTPS calls fire at once and the local network
# stack/security software kills the excess ones) are retried with backoff
# rather than failing the whole pipeline run outright.
MAX_CONNECTION_RETRIES = 3
CONNECTION_RETRY_BACKOFF_SECONDS = 2

# Firing many migrations at once means many concurrent threads all calling
# Gemini simultaneously. Opening that many fresh HTTPS connections to the
# same host at the same instant is what triggered WinError 10053 (connection
# aborted by local network stack/security software) -- cap how many Gemini
# requests run at once so bursts queue briefly instead of colliding.
_GEMINI_CONCURRENCY_LIMIT = threading.Semaphore(2)


_RETRIABLE_STATUS_CODES = {429, 500, 502, 503, 504}


def _post_with_retry(url, **kwargs):
    """requests.post wrapped with retry-on-transient-failure.

    Retries on: connection-level failures (e.g. WinError 10053 from too many
    simultaneous outbound connections), and 429/5xx HTTP responses (rate
    limiting or the provider's own servers being temporarily unavailable --
    seen in practice as a bare 503 from Gemini). Does NOT retry on other
    4xx errors (e.g. 400/401/404), since those are real request errors that
    won't succeed on a bare retry.
    """
    last_exc = None
    for attempt in range(MAX_CONNECTION_RETRIES + 1):
        try:
            resp = requests.post(url, **kwargs)
            if resp.status_code in _RETRIABLE_STATUS_CODES and attempt < MAX_CONNECTION_RETRIES:
                time.sleep(CONNECTION_RETRY_BACKOFF_SECONDS * (attempt + 1))
                continue
            return resp
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
            last_exc = exc
            if attempt < MAX_CONNECTION_RETRIES:
                time.sleep(CONNECTION_RETRY_BACKOFF_SECONDS * (attempt + 1))
                continue
            raise
    raise last_exc  # pragma: no cover - loop always returns or raises above


def call_azure(prompt: str, max_tokens: int = 8000, model: str | None = None):
    key = os.environ.get("AZURE_OPENAI_API_KEY")
    if not key:
        return None, "AZURE_OPENAI_API_KEY not set"

    deployment = model or AZURE_DEFAULT_MODEL
    url = (
        f"{AZURE_ENDPOINT}/openai/deployments/{deployment}/chat/completions"
        f"?api-version={AZURE_API_VERSION}"
    )

    budget = max_tokens
    last_finish_reason = None
    for attempt in range(MAX_TOKEN_ESCALATIONS + 1):
        try:
            resp = _post_with_retry(
                url,
                headers={"api-key": key, "Content-Type": "application/json"},
                json={
                    "messages": [{"role": "user", "content": prompt}],
                    "max_completion_tokens": budget,
                },
                timeout=180,
            )
            resp.raise_for_status()
            data = resp.json()
            choice = data["choices"][0]
            content = choice["message"]["content"]
            last_finish_reason = choice.get("finish_reason")

            if content:
                return content, None

            # Empty content + finish_reason="length" is the reasoning-token-
            # exhaustion signature: it consumed the whole budget on invisible
            # reasoning and never got to emit visible text. Double the budget
            # and retry rather than accepting an empty result.
            if last_finish_reason == "length" and budget < TOKEN_ESCALATION_CEILING:
                budget = min(budget * 2, TOKEN_ESCALATION_CEILING)
                continue

            return None, f"empty response (finish_reason={last_finish_reason})"
        except Exception as exc:  # noqa: BLE001 - surface any failure to the caller
            return None, str(exc)

    return None, (
        f"exhausted reasoning budget even at {budget} tokens "
        f"(finish_reason={last_finish_reason}) -- this input may need to be "
        f"chunked (e.g. per paragraph) rather than sent in one prompt"
    )


def call_gemini(prompt: str, max_tokens: int = 8000, model: str | None = None):
    # `model` is accepted for signature parity with call_azure but ignored --
    # Gemini always uses GEMINI_MODEL. Only Azure currently exposes a choice.
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return None, "GEMINI_API_KEY not set"
    with _GEMINI_CONCURRENCY_LIMIT:
        try:
            resp = _post_with_retry(
                GEMINI_URL,
                params={"key": key},
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {"maxOutputTokens": max_tokens},
                },
                timeout=180,
            )
            resp.raise_for_status()
            data = resp.json()
            return data["candidates"][0]["content"]["parts"][0]["text"], None
        except Exception as exc:  # noqa: BLE001
            return None, str(exc)


BACKENDS = {
    "azure": call_azure,
    "gemini": call_gemini,
}
