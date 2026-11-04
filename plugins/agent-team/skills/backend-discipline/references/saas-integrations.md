# SaaS Integrations Checklist (Auth, Payments, Email, OAuth, RLS)

Use this checklist when building or reviewing SaaS backend surfaces: authentication,
database access rules, Stripe billing, transactional email, background jobs, and
third-party OAuth integrations.

## 1. Official APIs & Credential Boundaries

- **Official, public APIs only, with the user's own keys.** Never call a
  competitor or reference app's private endpoints, never reuse its OAuth client
  ID, and never proxy through its services.
- **The user creates accounts and keys.** Agents never sign up for third-party
  services, enter payment cards, or paste live keys. The agent writes
  `.env.example` with every required variable name and empty/placeholder values;
  the user populates `.env.local` or host secrets.
- **Test mode first.** Use Stripe test keys (`sk_test_...`, `pk_test_...`) and
  sandbox environments until production cutover (`product-launch`).

## 2. Authentication & Account Lifecycle

- **Core flows**: email sign-up with verification, password reset, and magic
  link or OAuth (Google, Apple, GitHub) using the user's own developer apps.
- **Sessions**: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`) cookies.
  Provide a "sign out everywhere" / session revocation mechanism.
- **Roles & tenancy**: `owner`, `admin`, `member`, enforced through a single
  server-side policy function (`can(user, action, record)`) called on every read
  and write.
- **Real account deletion**: a user-initiated delete action that cascades or
  purges their personal data, active sessions, and billing subscriptions.
  **Apple App Store Review Guideline 5.1.1(v) mandates in-app account deletion**
  for any app that supports account creation.

## 3. Database Access Control & Multi-User Isolation

- **Row-Level Security (RLS) or explicit tenant scoping on every query**: every
  table holding user or tenant data must have RLS policies (e.g., Supabase /
  Postgres RLS) or pass through the server-side authorisation helper.
- **Second-user isolation test**: write an automated test where User B requests
  User A's record by ID or URL (`GET /items/:id`, `PATCH /items/:id`,
  `DELETE /items/:id`) and assert it returns `403` or `404` with zero leaked
  fields.
- **Seed script**: checked-in deterministic seed script using synthetic data
  (never real user PII).

## 4. Payments & Subscriptions (Stripe)

- **Stripe Checkout & Customer Portal**: use Stripe Checkout for plan sign-up
  and the Stripe Customer Portal for plan changes, payment method updates, and
  cancellation. Never build raw card input forms that touch PAN data directly.
- **Webhook verification & idempotency**:
  - Verify `Stripe-Signature` against the raw request body using the webhook
    signing secret before parsing.
  - Record processed `event.id` in a database table with a unique constraint so
    retries are a safe no-op.
  - Handle the four lifecycle events:
    1. `checkout.session.completed`
    2. `customer.subscription.updated`
    3. `customer.subscription.deleted`
    4. `invoice.payment_failed`
- **Database is the runtime source of truth**: webhook handlers update
  subscription status in your database; application routes read from your
  database, never from client claims or unverified redirect query parameters.
- **One-click cancellation**: cancelling a subscription must take one click in
  settings / Customer Portal. Dark-pattern retention mazes violate FTC click-to-cancel
  rules and EU consumer law, and are a top driver of 1-star reviews.

## 5. Transactional Email, Jobs & OAuth Lead Times

- **Transactional email**: send via Resend, Postmark, or SES from a verified
  custom domain (`SPF`, `DKIM`, `DMARC` configured). Write templates fresh.
- **Time-based jobs**: reminders, digests, sync, and cleanup run as idempotent
  background jobs with bounded retries and a dead-letter log. Store all
  timestamps in UTC; format in the user's IANA time zone at the edge.
- **OAuth verification lead times**: request the minimum scopes needed. Note in
  `docs/architecture.md` when an integration uses restricted/sensitive scopes
  (e.g., Google Calendar, Gmail, Drive) — Google OAuth verification takes
  several weeks before public users can sign in without an "unverified app"
  screen.

## 6. SaaS Security Pre-Ship Checklist

- [ ] Secrets only in env vars, `.env*` in `.gitignore`, `.env.example` committed with variable names only
- [ ] Every route validates input on the server with a schema (Zod / Pydantic / etc.)
- [ ] Every read and write checks object-level authorisation, verified by a second-user test
- [ ] Rate limits on login, sign-up, password reset, and any route that sends email or SMS
- [ ] Webhook handlers verify cryptographic signatures and deduplicate by event ID
- [ ] File uploads enforce size and MIME/magic-byte limits and serve from an isolated bucket/domain
- [ ] Privacy policy lists every sub-processor (Stripe, email provider, hosting, analytics)
