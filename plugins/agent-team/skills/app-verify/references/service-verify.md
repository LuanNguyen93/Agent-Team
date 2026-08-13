# Verifying an HTTP service

A service has no screen, so the temptation is to call a green suite the
verification. It is not. Almost everything that breaks a deployed API lives
outside the unit tests: dependency registration, configuration binding,
environment, migrations, auth wiring, serialisation, and the shape of the
error responses.

**Verification means: the service started, you sent real requests, you read the
responses and the logs.**

## 1. Start it the way the project starts it

Find the command from the project, not from memory: launch profiles
(`Properties/launchSettings.json`), `docker-compose.yml`, the `Makefile`, CI, or
the README. Note which profile and which environment you used - the same code
behaves differently under `Development` and `Production` because it binds a
different `appsettings.*.json`.

If it does not start, **that is the finding**. Report the startup output and
stop. A service that fails to boot has not been verified by anything.

Read the startup log even on success. It names the URLs it bound, the
environment, and usually the database it connected to. If it bound a different
port than you are about to call, everything after that is noise.

## 2. The failures that only appear at runtime

These are the reason this step exists at all - each one passes every unit test
and fails on the first real request.

- **A dependency never registered.** The container resolves at request time, not
  at build time, so a missing `AddScoped` compiles, boots, and then throws
  `Unable to resolve service for type ...` on the first call. Hit **every**
  endpoint the change touched, not just one.
- **A captive dependency** - something scoped resolved into a singleton. It
  works on the first request and misbehaves later, so hit the endpoint more than
  once before believing it.
- **Configuration that bound to nothing.** A renamed key leaves the options
  object with defaults and no error. Check the value the service actually used,
  from a log line or a diagnostic endpoint - not from the file you edited.
- **Migrations not applied.** The tests ran against an in-memory or freshly
  created database; the running service points at a real one that may be behind.
  Confirm the schema the service is talking to, and that the new column exists.
- **Serialisation naming.** Casing policy, enum-as-string, and null handling are
  set once in startup and are invisible in a unit test that compares objects.
  Read the raw JSON body, not a deserialised assertion.

## 3. Drive the real paths

For each endpoint the change touched:

1. **The happy path**, with a realistic body - not the minimal one the test uses.
2. **Without credentials.** Confirm it returns 401, and that a token for the
   wrong user or tenant returns 403 rather than someone else's data. A test that
   always runs authenticated never checks the gate is there.
3. **Invalid input.** Wrong types, a missing required field, a value past its
   bound. Confirm 400 with a body that matches the contract - not a 500 with a
   stack trace.
4. **The failure the change was meant to handle**, triggered on purpose. Stop
   the dependency, revoke the token, send the duplicate - whatever it is.
5. **The same request twice**, for anything a client may retry. See the
   idempotency rules in `backend-discipline`.
6. **An empty result**, not just a populated one. Zero rows is the case that
   returns `null` instead of `[]` and breaks the client.

Send them with a real HTTP client - `curl`, an `.http` file, or the project's
own collection. A Swagger UI is fine for exploring and poor for evidence,
because it does not show you what it sent.

## 4. Watch the other half

While driving, read:

- **The service log.** An exception that was caught and logged still happened.
  A warning about a retry, a slow query, or a failed background job is a
  finding even when the response was 200.
- **The database**, for anything that writes. Confirm the row landed, in the
  shape you expect, with UTC timestamps. A 200 is not proof of a commit.
- **Outbound calls**, if the change makes any. Confirm they had a timeout and
  that the failure path was exercised, not just described.

## 5. When the client is a separate track

If a frontend consumes this service, you are the first point where the real
client meets the real server. Watch the network traffic rather than the
rendered screen - a stub renders a perfect page. Confirm the client is calling
the running service, then walk each error case the contract named, since those
are the ones the stub modelled least honestly.

## 6. Evidence

State the command you started it with, the environment and URL it bound, and
for each request the method, path, status code, and the part of the body that
matters. Paste the actual output. "The endpoint works" is not a result.

If the service could not be started - no database, no connection string, a
missing secret - verification is **blocked**. That is a legitimate result to
report, and it is not a pass.
