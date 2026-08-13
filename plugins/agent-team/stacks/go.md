# Stack profile: Go

Applies when: `go.mod` at the module root.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| format | `test -z "$(gofmt -l .)"` | `gofmt -l` exits 0 and prints the offending files, so the list is the failure |
| vet | `go vet ./...` | the compiler is the typecheck; vet is the closest thing to a lint |
| test | `go test ./...` | add `-race` where the code is concurrent, and it usually is |
| build | `go build ./...` | opt-in via `AGENT_TEAM_RUN_BUILD=1`; `go test` already compiles |

Declare `.agent-team.json` explicitly to add `golangci-lint run`, `-race`, build
tags, or a workspace with more than one module.

## Conventions to detect and follow

- **Module path and Go version** in `go.mod`. The version decides whether
  generics, `errors.Join`, or range-over-func are available.
- **Layout**: `cmd/` for binaries, `internal/` for packages that must not be
  imported from outside the module. `internal/` is a dependency rule the
  compiler enforces for you - see `architecture-discipline`.
- **Error style**: wrapped with `fmt.Errorf("...: %w", err)` and inspected with
  `errors.Is` / `errors.As`. Follow what the codebase does; mixing sentinel
  errors and typed errors at random is the usual mess.
- **Test style**: table-driven tests with subtests, `_test.go` beside the code.
  Golden files under `testdata/`.
- **Linter**: `.golangci.yml` if present is authoritative, and it is the real
  lint gate rather than `go vet`.

## Things to check in review on this stack

- **An error assigned and not checked**, or `_ = doThing()`. In Go the error is
  the contract; discarding it is the defect.
- **`err` shadowed inside an `if` or a closure**, so the outer error is never
  the one returned.
- **A goroutine with no way to stop** - no context, no done channel. It outlives
  the request and holds whatever it captured.
- **A `context.Context` accepted and then not passed on**, or `context.TODO()`
  left on an I/O path. A context that stops at the first layer cancels nothing.
- **A loop variable captured by a goroutine** on Go versions before 1.22.
- **A mutex copied** by value, usually by putting a struct containing one into a
  slice or passing it by value. `go vet` catches most of these - read its output
  rather than trusting the build.
- **`defer` inside a loop**, which holds every resource until the function ends.
- **A missing `rows.Close()` / `resp.Body.Close()`**, especially on the error
  path, and a `defer Close()` before the error from the call was checked.
- **`http.Get` and friends with no timeout** - the default client has none, so a
  hung dependency hangs the caller forever. Set one on the client, not per call.
- **A slice retained from a larger array**, keeping the whole backing array
  alive - relevant when parsing large payloads.
- **`interface{}` / `any` where a concrete type or a small interface would do**,
  and interfaces declared at the implementation rather than at the consumer.
- **Unbounded channel buffers or worker counts** driven by an input the caller
  controls.
