# The model as a dependency

A model call is remote I/O with three properties ordinary I/O does not have: it
costs money per call, it is not idempotent, and its output is attacker-
influenced whenever any part of its input is.

## Treat the call like the network call it is

- **Always set a timeout.** Most SDK defaults are generous or absent, and a hung
  model call holds a request, a connection, and a thread pool slot.
- **Retry carefully.** The call is expensive and non-idempotent: a naive retry
  can double a charge or duplicate a side effect. Retry only on a timeout or a
  5xx/429, with backoff, with a hard attempt cap, and never around a call that
  already performed a side effect.
- **Bound the input.** Anything user-supplied or retrieved must be truncated to
  a known budget before it goes in. "The context window is large" is not a
  bound - it is a cost and a latency you did not choose.
- **Bound the output.** A max token limit, and code that handles a response cut
  off mid-structure. Truncated JSON is the most common parse failure in
  production.
- **Bound the loop.** An agent that can call tools needs a maximum iteration
  count and a maximum spend, decided before it runs. Without both, a loop that
  fails to converge fails expensively.
- **Handle the error paths that only exist here**: rate limit, content filter,
  context length exceeded, a refusal, and a valid response that is not valid
  JSON. Each needs a decision, not a generic 500.

## Pin the model

An unpinned alias changes behaviour under you with no error, no deploy, and no
diff. Anything you have measured must name an exact version, and the version
belongs in configuration where it can be seen and changed deliberately.

When the model version changes, the evals run again. A model upgrade is a
behaviour change, and it is the one class of change that arrives without a
commit.

## Untrusted content in a prompt is a trust boundary

`backend-discipline` says the trust boundary is on the server and you authorise
the object, not the route. That still holds, and there is now a second boundary:
**anything that reaches the prompt can try to instruct the model.** A retrieved
document, a web page, a file the user uploaded, a database field another user
wrote, and the output of a tool are all untrusted input.

The consequences to design for:

- **Never let model output alone authorise an action.** If the model decides to
  call a tool that deletes, sends, pays, or reads another user's data, the
  server re-checks that the *user* is permitted to do it, with the same
  authorisation code an ordinary endpoint would use. The model proposes; the
  server decides.
- **Separate instructions from data.** Put untrusted content in a clearly
  delimited section and say it is data to be processed, not instructions. This
  reduces the failure rate; it does not eliminate it, so it is never the only
  control.
- **Constrain what a tool can do**, not just when it is called. A tool that can
  read any row is a data leak waiting for one convincing paragraph; scope it to
  the caller's tenant at the query level.
- **Validate output before it is used.** Parse into a schema, check enums and
  ranges, and reject rather than coerce. Never evaluate generated code, never
  interpolate model output into SQL or a shell command, and escape it before it
  reaches HTML.
- **Assume anything in the prompt can come back out.** A system prompt is not a
  secret, and a document another tenant owns must never be in the context in
  the first place.

## Data going out

- **Know what leaves.** Sending user data to a third-party provider is a
  disclosure. Confirm it is allowed for this data class before writing the call,
  not after.
- **Do not log full prompts** containing personal data, and do not put them in
  an error report that ships to a third party. Log an identifier and the
  metadata; store the content where the rest of your personal data lives, under
  the same retention.
- **Redact before the call** where the model does not need the identifier at all.

## Cost and latency are budgets

State them the way you would state a query bound:

- Tokens in and out per call, and calls per user action. A chain of four calls
  is four times the latency and four times the failure surface.
- **Cache what repeats** - identical prompts, embeddings of unchanged documents,
  retrieval results for a hot query. Embedding the same corpus on every deploy
  is a common and invisible waste.
- **Stream** where the user is waiting on prose. It does not make it faster; it
  makes the wait honest.
- Say the cost per operation when you report the work, and flag anything that
  scales with a user-controlled number.
