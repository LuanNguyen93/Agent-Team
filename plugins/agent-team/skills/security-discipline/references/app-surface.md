# The application surface

What `SKILL.md` leaves to this file: the request-handling mistakes that
`backend-discipline`'s "validate at the edge, authorise the object" does not
name one by one. Each entry is how the guarantee is lost in practice, and the
control that actually holds. The SAST gate (semgrep) catches the mechanical
shapes of most of these; it does not catch the design ones.

## Injection, by family

- **SQL / NoSQL** — parameters, never string assembly, including in the ORM's
  raw escape hatch and in `ORDER BY` / column names, which parameters cannot
  carry: allowlist those. A NoSQL operator (`$gt`, `$where`) arriving inside a
  JSON body is the same bug wearing different syntax - reject objects where a
  scalar was expected.
- **Command** — no shell. Call the binary with an argument array; if a shell is
  unavoidable, the user never contributes more than a single allowlisted token.
- **Template / expression** — user input is rendered *by* a template, never
  *as* one. Server-side template injection is remote code execution.
- **Mass assignment** — bind the request to an explicit allowlist of fields, not
  to the model. `isAdmin`, `tenantId`, `price` arrive in the body the first time
  someone reads the API.
- **Deserialization** — never deserialise untrusted input into live objects
  (pickle, Java serialisation, YAML `load` without the safe loader, PHP
  `unserialize`). Use a data-only format and a schema.
- **Path** — `join(base, userInput)` is traversal; resolve and then check the
  result still starts with `base`, or map ids to paths server-side.

## SSRF

Any URL the user supplies and the server fetches - webhooks, "import from URL",
image proxies, PDF renderers, link previews - points at the inside of your
network by default: `localhost`, the cloud metadata endpoint
(`169.254.169.254`), internal admin ports, other tenants' services.

- Allowlist schemes (`https` only) and, where the use case permits, hosts.
- Resolve DNS, then reject private, loopback, link-local and metadata ranges
  **on the resolved address**, and pin the connection to that address -
  checking the hostname and then letting the client re-resolve is the standard
  bypass (DNS rebinding).
- Do not follow redirects blindly; re-check every hop.
- Run the fetcher with no credentials and, ideally, on a network segment that
  cannot see the rest.

## Authentication mechanics

- **Passwords**: argon2id or bcrypt with a current work factor; never a fast
  hash, never home-rolled. Compare with a constant-time function. Respond to
  "wrong password" and "no such user" identically and in the same time.
- **Sessions**: rotate the session id on login and on privilege change
  (fixation); invalidate on logout server-side, not just by clearing the cookie;
  absolute and idle expiry; cookie `HttpOnly`, `Secure`, `SameSite=Lax` or
  stricter.
- **JWT**: verify the signature with a pinned algorithm (`alg` from the token is
  attacker input - `none` and RS→HS confusion are the classic bugs); check
  `exp`, `iss`, `aud`; keep them short-lived because they cannot be revoked;
  never store anything in one that the client must not read.
- **Reset and magic links**: single-use, short expiry, bound to the account,
  random from a CSPRNG; the response never reveals whether the address exists.
- **MFA / step-up** for anything that changes credentials, payout details, or
  permissions; enforce it server-side per action, not as a flag the client
  sends.
- **Webhooks you receive**: verify the provider's signature over the raw body
  with constant-time compare, check the timestamp to stop replay, and treat the
  payload as untrusted even after verification.

## CSRF

Applies whenever auth rides in a cookie the browser attaches automatically.
`SameSite` is the first line, not the only one: a synchroniser token or the
double-submit pattern on every state-changing request, and state changes never
on `GET`. A bearer token in an `Authorization` header set by script is not CSRF-
vulnerable, which is the one argument for it over cookies - weighed against the
`localStorage` exposure in `SKILL.md`.

## File upload

- Decide type by **content** (magic bytes) and by an allowlist, never by the
  `Content-Type` header or the extension the client chose; then re-encode
  images and strip metadata.
- Enforce a size limit before the body is read into memory.
- Store outside the web root, under a server-generated name, and serve with
  `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff` -
  an uploaded HTML or SVG file served inline from your origin is stored XSS.
- Scan with an AV engine where the files are redistributed to other users.

## Security headers and CSP

Set once, at the edge, for every response:

```
Content-Security-Policy: default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

A CSP with `'unsafe-inline'` in `script-src` is not a CSP. Use nonces or
hashes; start in `Content-Security-Policy-Report-Only` on an existing app and
tighten from the reports. `frame-ancestors` replaces `X-Frame-Options`.

## Cryptography you are allowed to do

Use the platform's high-level API (libsodium, `crypto.subtle`, the language's
`secrets`/`crypto` module) for: random tokens (CSPRNG, at least 128 bits), AEAD
encryption (AES-GCM or ChaCha20-Poly1305 with a unique nonce), password
hashing (above), HMAC for integrity. Do not: build a protocol, reuse a nonce,
use ECB, use MD5/SHA-1 for anything security-relevant, or put keys next to
the data they protect. Keys live in a KMS or secret manager and have a
rotation story from day one.

## What the SAST gate sees, and what it does not

`semgrep` (the `SAST` gate in `run-gates.sh`) flags the mechanical shapes -
string-built SQL, `exec` on a shell, `innerHTML`, `yaml.load`, a missing
`SameSite`, a weak hash. It cannot see a missing authorisation check, a tenant
id taken from the body, a reset token that is not single-use, or a CSP that is
set but hollow. Those are read, by the reviewer, against this file.
