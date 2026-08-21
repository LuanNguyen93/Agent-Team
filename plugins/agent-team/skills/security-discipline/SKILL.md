---
name: security-discipline
description: The security rules that survive contact with production - secrets and rotation, dependency and supply chain risk, authorisation on the object, the browser surface, audit logging and rate limits, and what counts as personal data. Use when planning, writing, or reviewing any code that handles input, identity, money, or personal data.
when_to_use: Adding an endpoint or a screen, taking a new dependency, touching auth, storing user data, or reviewing any of those. Do NOT use as a substitute for the project's own threat model or for a formal audit.
---

# Security discipline

Two rules underneath everything here:

1. **The attacker does not use your UI.** Every guarantee that lives only in the
   client is a suggestion.
2. **Absence of a finding is not a finding of absence.** A scanner that did not
   run, a dependency file you did not open, an auth path you did not read — say
   so. Silence reads as "clean" and it is not.

## Where this sits

Server-side mechanics — validation at the edge, authorising the object,
transaction scope, idempotency — are `backend-discipline`. This skill is what
that one deliberately does not cover: secrets, the dependencies you did not
write, the browser, and the data itself.

## Secrets

- **A committed secret is a leaked secret.** Git history is forever, and so is
  every clone, fork, CI cache, and backup. The fix is **rotate the credential**,
  not amend the commit. Rewriting history is cleanup afterwards, never the
  remedy.
- Never print a secret to make debugging easier, including into a test fixture,
  an error message, a snapshot file, or a log line "just for now".
- Config comes from the environment or a secret manager. A default value baked
  into code for local convenience is the value that ships.
- Anything shipped to a device or a browser is public — see the frontend section.
- If you find a secret in the working tree or the history, **stop and tell the
  user**. Do not silently remove it; they need to rotate it, and they can only
  do that if they know.

The **secret-scan gate** (gitleaks or trufflehog over the working tree) runs with
the other gates. It scans the tree rather than the history, because a hit in the
history needs a rotation decision from the user, not a blocked task. No scanner
installed means the gate is **absent** — nothing checked.

## Dependencies you did not write

Most of the code you ship, you did not review. Treat it that way.

- Every project gets a **dependency audit gate** — the commands per stack, and
  what to do with a CVE that has no fix, are in `references/supply-chain.md`.
- **Adding a dependency is a decision, not a detail.** Say why the standard
  library or an existing dependency will not do. A transitive tree of forty
  packages to avoid twelve lines is a bad trade.
- Install from the **lockfile**, never resolve fresh. `npm ci`, `pip install -r`
  with hashes, `go mod verify`, `cargo --locked`.
- Check the name before you install it. Typosquats and abandoned packages
  transferred to a new maintainer are the common path in, not exotic ones.

## Authorisation

`backend-discipline` states the rule; these are the ways it is lost in practice:

- **Every handler**, not one middleware you assume runs. Check the route table
  for the handlers that opted out - a middleware with an exclusion list is the
  usual way the object check quietly stops applying.
- Enumeration: sequential ids leak how many customers you have, and let an
  attacker walk them. Random ids do not make you authorised — they make the
  failure quieter.
- The difference between 401, 403 and 404 can itself leak. Decide deliberately
  which one an unauthorised user sees for a resource that exists.
- Multi-tenant: the tenant comes from the **session**, never from the request
  body or a header the client controls.

## The browser surface

- **Render, do not inject.** `dangerouslySetInnerHTML`, `v-html`,
  `innerHTML`, and template interpolation into a `<script>` are the XSS
  surface. If untrusted HTML must render, sanitise with a maintained library —
  never a regex.
- Tokens in `localStorage` are readable by any script that lands on the page,
  including a compromised dependency. Prefer an httpOnly cookie with `SameSite`.
- `postMessage` handlers must check `event.origin`. A CORS policy of `*` on an
  endpoint that reads a cookie is a data leak.
- Every value in a frontend bundle is public: API keys, feature flags, internal
  URLs, commented-out code. So is everything in a mobile app bundle.
- Redirect targets and file paths taken from user input are open-redirect and
  path-traversal, respectively. Allowlist; do not sanitise.

## The request surface

Injection by family (SQL, command, template, mass assignment, deserialization,
path), SSRF, authentication mechanics (hashing, sessions, JWT, reset links,
MFA, webhook signatures), CSRF, file upload, security headers and CSP, and the
cryptography you are allowed to do - each is one paragraph in
`references/app-surface.md`, stated as the way it is lost in practice. Read it
before adding an endpoint that fetches a URL, accepts a file, or touches login.
The **SAST gate** (semgrep, via `run-gates.sh`) catches the mechanical shapes;
the design mistakes it cannot see are listed at the end of that file.

## Make abuse visible and expensive

- **Audit log** anything that moves money, changes permissions, exports data, or
  deletes it: who, what, when, from where, and the outcome — including denials.
  A denied attempt nobody recorded is an attack nobody will ever see.
- **Rate limit** authentication, password reset, anything that sends a message
  or costs money per call, and any expensive query. Limit by account *and* by
  source, because either alone is trivially avoided.
- Failed logins should be slow and identical in response regardless of whether
  the account exists.

## Personal data

Decide the classification **when the column is created**, not when the incident
happens. For every field: is it personal, sensitive, or neither; who may read
it; how long it is kept; what happens on a deletion request.

- Do not collect what you do not need. The safest field is the absent one.
- Personal data must not reach logs, analytics, error trackers, LLM prompts, or
  a non-production database seeded from a production dump.
- Deletion means deleted — including backups policy, derived tables, caches, and
  search indexes. If it does not, say what actually happens.

## Infrastructure, containers, and CI

The YAML beside the code is where the blast radius lives, and it is the part
that usually skips review. Running as root, a `:latest` base image, a bucket
that is public by accident, `0.0.0.0/0`, an IAM `Action: "*"`, a Terraform state
file in the repository, an unpinned third-party CI action, `pull_request_target`
checking out a fork — `references/iac-and-containers.md` has each of these with
what to do instead.

CI is production: it holds the credentials for everything it deploys to.

## When you are designing rather than fixing

Enumerate the trust boundaries and the abuse cases before the shape is fixed;
`references/threat-modeling.md` is the short version that fits in a planning
session.

## Reporting

Per `handoff-contract`, label what you checked and what you did not. A security
statement without its scope is worse than none, because it is trusted.

> Checked: authz on the three new handlers, input validation, the audit gate.
> Not checked: the existing session middleware, IaC, the CI runner's permissions.
