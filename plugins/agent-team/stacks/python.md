# Stack profile: Python

Applies when: `pyproject.toml` or `setup.cfg` at the project root.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| format | `ruff format --check .` | fails on diff; never plain `ruff format` in a gate - that edits |
| lint | `ruff check .` | replaces flake8, isort, pyupgrade and most of pylint |
| typecheck | `mypy .` | only where the project configures it - see below |
| test | `pytest -q` | |

The runner discovers these, and prefixes them with `uv run` or `poetry run` when
a matching lockfile is present - a bare `ruff` on `PATH` is not the same tool as
the one in the project's environment.

**A tool that is not configured is not a gate.** Running `mypy` on a codebase
that never annotated anything produces hundreds of findings that gate nothing.
The runner only runs what `pyproject.toml` mentions.

**A missing linter is a skipped gate; a missing `pytest` on a project that has
tests is a failure.** The difference is that one gate is absent by choice and
the other is unverifiable, and unverifiable must never read as a pass.

## Conventions to detect and follow

- **Environment manager**: `uv.lock`, `poetry.lock`, `requirements.txt`, or a
  bare venv. This decides every command you type; read it before running one.
- **Python version**: `requires-python` in `pyproject.toml`. Match syntax to it.
- **Layout**: `src/<package>/` or a flat `<package>/` at the root. Tests in
  `tests/`, named `test_*.py`.
- **Async**: whether the codebase is asyncio-based. Mixing sync I/O into an
  async path is the usual performance defect, and it does not fail any test.
- **Settings**: `pydantic-settings` or plain `os.environ`. Follow what exists.
- **Type strictness**: `strict = true` under `[tool.mypy]` changes what is
  acceptable far more than the presence of mypy does.

## Skills that apply

`backend-discipline`, `architecture-discipline`, `quality-gates`,
`code-navigation`, `context-discipline`, `tdd-discipline`, and for anything
calling a model, `ai-engineering`.

## Things to check in review on this stack

- **Mutable default argument** (`def f(x=[])`) - shared across every call.
- **A bare `except:` or `except Exception:`** that logs and continues, and
  `raise e` instead of a bare `raise`, which resets the traceback.
- **Blocking I/O inside an async function** - `requests`, `time.sleep`, a sync
  DB driver. It stalls the whole event loop and no test notices.
- **A missing `timeout=`** on any `requests` / `httpx` call. The default is
  no timeout, which means a hung dependency hangs your process.
- **Resources not closed** - a file or client opened without a context manager,
  especially on the error path.
- **`datetime.now()`** on anything stored or compared;
  `datetime.now(timezone.utc)`.
- **Floats for money.** `Decimal`, or integer minor units.
- **Module-level side effects** - a client constructed or a config read at
  import time makes the module untestable and the failure order-dependent.
- **`from module import *`**, and circular imports resolved by importing inside
  a function - the second is a symptom of a layering violation, see
  `architecture-discipline`.
- **N+1 in an ORM** - a lazy relationship touched inside a loop. `select_related`
  / `selectinload` / `joinedload` depending on the ORM.
