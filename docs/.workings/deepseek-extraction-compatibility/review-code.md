# Code review: DeepSeek extraction compatibility

Date: 2026-09-02

## Scope reviewed

- DeepSeek request prompt and SSE decoder.
- Shared ordered structured-output parser.
- Protected live Provider contract gate and its report schema.
- All direct parser and gate call sites found by a repository-wide search.

## Review layers

### 1. Public behavior

The repair changes only DeepSeek extraction behavior: an observed single `text` field is emitted as the application's canonical source stream. Translation remains a one-request image operation and still requires ordered source and translation fields. Failure remains terminal and user-retried; no automatic request was added.

### 2. Boundary and data flow

The compatibility is selected by `DeepSeekChatStreamDecoder` when its operation is extraction. The shared parser defaults to canonical `source`, so OpenAI, Gemini, and every translation path remain strict. The parser still enforces a single allowed result shape, field order, complete JSON, terminal metadata, clean completion, and rejection of extra fields.

The extraction prompt now asks DeepSeek for the canonical `source` field first. The alias is therefore a defensive compatibility boundary for the experimentally observed response rather than the preferred output contract.

### 3. Failure and security behavior

Malformed, reordered, incomplete, truncated, or extra output still fails without retaining partial text. Live reports contain only Provider, model, operation, normalized stage/status, duration, hashed request ID, and token usage. They contain neither API keys, image bytes, generated text, nor raw Provider responses.

The live gate emits one report per Provider operation. It runs extraction and translation independently, so a failure in one operation does not suppress evidence for the other.

### 4. Consistency and maintainability

Repository-wide call-site review found OpenAI and Gemini still use the parser's canonical initializer. DeepSeek translation explicitly passes only `source`; only DeepSeek extraction passes `source` and `text`. The new operation field is supplied at every report construction site and is serialized using stable values `extract` and `translate`.

## Findings

No unresolved correctness, security, or maintainability finding remains in the changed scope.
