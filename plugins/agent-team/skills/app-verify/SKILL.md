---
name: app-verify
description: Verify a change by running the real application and driving it - mobile, desktop, CLI, or service - for the cases a browser cannot cover. Use before declaring work done on anything that is not a web page.
when_to_use: Verifying a Flutter, mobile, desktop, CLI, or backend service change end to end. Use browser-verify instead when the surface is a web page. Do NOT use as a substitute for the quality gates.
---

# Application verification

A green suite says the code does what the tests describe. It does not say the
app works — wiring, DI, config, permissions, platform channels, and startup all
sit outside most unit tests, and that is where features break.

**Verification means: the app ran, you drove it, you saw the result.**
Everything else is inference, and must be labelled as such.

## 1. Run it for real

Find the run command from the project, not from memory: `pubspec.yaml` scripts,
`Makefile`, `justfile`, CI config, or the README.

| Surface | Start it | Drive it |
|---|---|---|
| Flutter | `flutter run -d <device>` | `flutter test integration_test`, or by hand |
| Mobile native | the platform's run command, on a simulator | the platform's UI test runner |
| Desktop | the run command | by hand, and record what you did |
| CLI | run the binary | real arguments, including the failure cases |
| Service | start it | `curl` / an HTTP client against the real endpoint |

If it does not start, **that is the finding**. Stop and report it. Do not look
for a way to test around a broken app.

`flutter devices` first — no device or emulator means verification is
**blocked**, which is a legitimate result to report. It is not a pass.

## 2. Drive the actual path

Follow the path a user takes, not the path the test takes:

1. Cold start. First launch after install behaves differently from a hot reload,
   and hot reload hides exactly the bugs that ship.
2. The happy path, end to end, with real input.
3. The failure the change is supposed to handle — trigger it deliberately.
4. Come back: background the app and return, or restart it. State that does not
   survive is a defect users hit constantly and tests rarely do.

## 3. Check what unit tests do not

- **Console and logs while driving** — an exception that is caught and logged
  still ran. Read the output; do not assume silence.
- **Empty, loading, and error states** — reach each one on purpose. Kill the
  network to reach the error state; do not just read the code that handles it.
- **Permissions**, on a device that has not granted them yet.
- **Layout at the extremes**: the narrowest supported screen, the largest text
  scale, the longest realistic string, the 500-row list.
- **Offline and slow network**, for anything that fetches.

## 4. Evidence

State what you ran, on what device or platform, and what you observed. A
screenshot or the actual log output beats a description of it.

Then state, explicitly, **what you did not verify and why**: no device, no
credentials, a platform you cannot run. Per `handoff-contract`, an unverified
path is `[assumed]`, and saying so is what makes the report usable.

Never report a flow as working because the code looks correct. That is the exact
substitution this skill exists to prevent.
