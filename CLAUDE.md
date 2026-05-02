# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Durex is a package that assists in save Genserver state to an external server

## Commands

```bash
# Run all code quality checks (preferred before commits)
mix precommit  # or: mix check

# Individual quality checks
mix format --check-formatted
mix credo --strict
mix doctor
mix dialyzer
mix test
```

## Architecture

### Application Structure

- `LeadRouter` - Core business logic contexts
  - `Accounts` - User management, authentication tokens, magic link auth, accounts, memberships, API keys
  - `Accounts.Scope` - Multi-tenant scoping by user
  - `Leads` - Lead collection and qualification lifecycle
  - `Leads.Token` - JWT token generation/verification for lead-scoped auth (Joken)
  - `Leads.TokenBlocklist` - In-memory ETS blocklist for revoked lead JWTs (GenServer)
- `LeadRouterWeb` - Web layer (controllers, LiveViews, components)
  - Uses Bandit as HTTP server
  - Tailwind CSS 4 for styling
  - DaisyUI components available

### Multi-Tenancy Model

The app uses an Account-based multi-tenancy model:
- **User** - Authenticated via magic link (no passwords by default)
- **Account** - Organization/tenant with a unique slug and active/suspended status
- **AccountUser** - Join table with role (`:owner`, `:admin`, `:member`)
- **ApiKey** - Scoped to an AccountUser membership, not directly to a User

### Dual Authentication System

1. **Browser auth**: Magic link based (see `LeadRouter.Accounts` and `LeadRouterWeb.UserAuth`)
2. **API auth** (two separate mechanisms):
   - **API Keys** (`ApiAuth` plug): Bearer token with `pk_` (read-only) or `sk_` (read/write) prefix. Verifies via prefix lookup + hash comparison. Sets `current_api_key`, `current_account_user`, `current_user`, `current_account` assigns.
   - **Lead JWTs** (`LeadTokenAuth` plug): Short-lived JWT (1hr) returned from lead creation. Used for lead update/qualify. Token's `lead_id` claim must match URL path `:id`. Tokens are invalidated after lead qualification via the ETS blocklist.

### Lead Lifecycle

Leads progress through: `draft` → `qualified`
- **Create** (public, no auth): Returns lead ID + JWT token
- **Update** (JWT required): Merges JSONB fields (`metadata`, `data`) shallowly
- **Qualify** (JWT required): Transitions draft → qualified, triggers distribution, invalidates JWT

### Timezone Resolution

- `Lead.timezone` stores an IANA timezone name and `Lead.timezone_source` records whether it came from the client or ZIP-based server resolution
- ZIP resolution uses `LeadRouter.Geo.Timezone` backed by the `zip_timezones` table and ETS cache
- `app/priv/data/uszips.csv` is the source of truth for the ZIP-to-timezone seed data

### API Routes

Routes are under `/api/v1/accounts/:account_id/leads`. OpenAPI docs served at `/api/v1/docs` (Swagger UI) and `/api/v1/openapi` (spec JSON). Uses `open_api_spex` with controller-level `operation` macros.

Phone verification endpoints:
- `POST /api/v1/accounts/:account_slug/leads/:id/verify-phone`
- `POST /api/v1/accounts/:account_slug/leads/:id/verify-phone/confirm`

In development, phone verification static mode is enabled by default:
- `verify-phone` bypasses Telnyx send
- `verify-phone/confirm` accepts static code `123456`
- Toggle with `LEAD_ROUTER_DEV_STATIC_MODE=true|false` or `config :lead_router, :phone_verification`

### Router Pipelines

- `:api` - Base (no auth, JSON + OpenAPI spec + CORS)
- `:api_authenticated` - Requires valid API key (read access)
- `:api_write` - Requires private API key (`sk_` prefix)

Rate limits: auth 5/min, API 100/min, leads 60/min (per IP via Hammer)

### Key Patterns

**Scoped queries**: The app uses `LeadRouter.Accounts.Scope` for user-scoped data access. Check config in `config/config.exs` under `:scopes`.

**HTTP Client**: Always use `Req` (never HTTPoison/Tesla) - see mix.exs comment.

**Testing**: Uses Mimic for mocking. Test support in `test/support/` with `ConnCase` and `DataCase` helpers. Use `register_and_log_in_user` setup helper for authenticated tests.

### Environment Variables

Uses dotenvy for local development. Files loaded (in priority order):
1. `.env.{dev|test}.local`
2. `.env.{dev|test}`
3. `.env.local`
4. `.env`

Production requires: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `GOODAUDIT_API_URL`, `GOODAUDIT_API_KEY`

Optional (dev/test): `GOODAUDIT_API_URL`, `GOODAUDIT_API_KEY` — enables audit trail delivery to GoodAudit service

### Observability (OpenTelemetry)

Distributed tracing via OpenTelemetry ships to Better Stack. Toggle with `OTEL_ENABLED=true|false`.
- Capability spec: `openspec/changes/add-opentelemetry/design.md`
- Runbook: `docs/runbooks/observability-runbook.md`
- Setup module: `lib/lead_router/open_telemetry.ex`
- Ecto db.statement is disabled in spans to prevent PII exposure

### Variant Assignment Telemetry

- `[:lead_router, :variant_assignment, :new]` — emitted when a visitor is assigned to a variant for the first time. Metadata: `%{questionnaire_id, variant_id}`, measurement: `%{count: 1}`.
- `[:lead_router, :variant_assignment, :sticky]` — emitted when a returning visitor's existing assignment is returned. Metadata: `%{questionnaire_id, variant_id}`, measurement: `%{count: 1}`.

## Experiment Lifecycle

Questionnaire experiments enable A/B testing of questionnaire variants:

1. **Prerequisite:** Questionnaire must have `multi_live_enabled = true` with 2+ live variants
2. **Create** (`Experiments.create_experiment/2`): Creates a `:draft` experiment with participant variants and traffic weights
3. **Start** (`Experiments.start_experiment/2`): Transitions to `:running`, validates weights sum to 100 and all variants are `:live`
4. **Stop** (`Experiments.stop_experiment/2`): Transitions to `:stopped`, pauses traffic splitting
5. **Declare Winner** (`Experiments.declare_winner/3`): Transitions to `:decided`, archives losing variants, sets `current_variant_id` to winner

Only one experiment per questionnaire may be `:running` at a time (enforced by unique partial index).

**Stats module** (`Experiments.Stats`): Computes per-variant exposures, completions, conversion rate, and Bayesian win probability via Monte Carlo sampling from Beta posteriors. Results cached 30s per experiment.

**Dashboard route:** `/dashboard/accounts/:slug/questionnaires/:id/experiment`

**Telemetry events:**
- `[:lead_router, :experiment, :winner_declared]` — emitted when a winner is declared. Metadata: `%{experiment_id, winning_variant_id, actor_id}`.

## Code Quality

Credo runs in strict mode. Key settings:
- Max line length: 120 chars
- Max nesting: 2 levels
- TODOs are errors (exit status 2)
- Alias usage required when nested >2 deep

## Phoenix/Elixir Guidelines

### Router Scopes
Router `scope` blocks include an optional alias prefix. Never create redundant aliases:
```elixir
# The scope provides AppWeb.Admin prefix automatically
scope "/admin", LeadRouterWeb.Admin do
  live "/users", UserLive  # Points to LeadRouterWeb.Admin.UserLive
end
```

### LiveView
- Use streams for collections (never regular list assigns)
- Streams: `stream/3`, `stream_insert/3`, `stream_delete/3` with `reset: true` for filtering
- Never use deprecated `phx-update="append"` or `phx-update="prepend"`
- Colocated JS hooks must start with `.` prefix (e.g., `.PhoneNumber`)
- Always give forms unique DOM IDs

### HEEx Templates
- Use `{...}` for attribute interpolation, `<%= %>` for block constructs in bodies
- Class lists require `[...]` syntax: `class={["base", @cond && "conditional"]}`
- Comments: `<%!-- comment --%>`
- Literal curly braces need `phx-no-curly-interpolation` on parent tag

### Ecto
- Preload associations when they'll be accessed in templates
- Use `Ecto.Changeset.get_field/2` for changeset field access
- Fields set programmatically (like `user_id`) must not be in `cast` calls

### Forms
- Always use `to_form/2` assigned in LiveView: `assign(socket, form: to_form(changeset))`
- Template: `<.form for={@form} id="unique-id">` with `<.input field={@form[:field]} />`
- Never pass changesets directly to templates

### Testing
- Use `start_supervised!/1` for processes in tests
- Avoid `Process.sleep/1` - use `Process.monitor/1` and assert on DOWN messages
- Use `LazyHTML` for HTML assertions in LiveView tests

### Tidewave MCP server
- Use it to read the docs for Elixir packages
- Use it to read the logs for the Phoenix application

### Coding Rules

- If you are asked to fix a bug YOU MUST add a test that reproduces the bug and then fix the bug
- Whenever you think you're finished making a change the user requested, run a `mix check` to check for compilation errors, test regressions, and code quality
- When adding a *large* feature or change, add a test as well. For small changes use your best judgement.
- Prefer Phoenix.JS commands over storing state on assigns wherever possible
- Avoid custom JS wherever possible! Do not write custom JS when you can use Phoenix.JS commands (like `phx-click={JS.hide(...)}`)
- When unit testing LiveViews, make sure every code path involving a `handle_*` function is tested
- When state can be stored sensibly in a query param instead of assigns, prefer that
- Don't try to start the dev server because the developer should already be running it in the background
- When adding tests make sure to make them async if you can
- Use the new Phoenix `{@foo}` syntax instead of the old `<%= @foo %>` syntax
- Use the Phoenix Components in `core_components.ex` (e.g., `<.button>` instead of `<button>`)
- If you get really stuck debugging something, try adding debug statements and asking the developer to manually test, then read the logs with Tidewave MCP
- Fill in the `@moduledoc` attribute for modules
- Add `@spec` for every function
- When creating UI use the DaisyUI component library when possible
- When creating UI prefer re-usable functional HEEx components when it makes sense
- All modals should be dismissable with an esc key
- Use Faker when generating test data and seed data
- YOU MUST keep the seed data up to date
- Use `ExUnit.CaptureLog` if there are any errors getting logged in tests
- YOU MUST fix all broken tests before committing changes
- Put all secrets config in the `runtime.exs` file and use `System.get_env/1` to access them
- Status fields should be at the top of the UI
- When adding a new notification event type to `Event.ex`, you MUST also add a matching `build/3` clause in `Notifications.Emails` and a `build/2` clause in `Notifications.Messages` with content specific to that event type. Every event type must have its own default email and SMS message — never rely on the generic fallback for known events.

## Dashboard Design System

The dashboard uses a warm amber/slate theme (DaisyUI custom themes in `app.css`). All dashboard pages must follow these patterns — reference `dashboard_live.ex` as the canonical example.

### Page Structure
- Wrap page content in `<div class="space-y-6">` for consistent vertical rhythm
- Do NOT use the generic `<.header>` component — use direct markup matching the dashboard pattern

### Page Header
```heex
<div class="flex items-end justify-between">
  <div>
    <h1 class="text-xl font-bold tracking-tight text-base-content">Page Title</h1>
    <p class="mt-0.5 text-sm text-base-content/50">Description text.</p>
  </div>
  <%!-- Optional action button --%>
</div>
```

### Content Cards
All data panels (tables, lists, detail views) go inside bordered card containers:
```heex
<div class="rounded-xl border border-base-300/60 bg-base-100">
  <div class="flex items-center justify-between border-b border-base-300/40 px-5 py-3.5">
    <h2 class="text-sm font-semibold text-base-content">Section Title</h2>
    <span class="text-xs text-base-content/40">Optional meta</span>
  </div>
  <div class="p-5"><%!-- Content --%></div>
</div>
```

### Typography Scale
- Page title: `text-xl font-bold tracking-tight text-base-content`
- Page subtitle: `text-sm text-base-content/50`
- Card/section title: `text-sm font-semibold text-base-content`
- Labels: `text-xs font-medium text-base-content/50 uppercase tracking-wide`
- Meta/secondary: `text-xs text-base-content/40`

### Color Opacity Pattern
Use fractional opacities for hierarchy: `/50` for secondary text, `/40` for meta, `/30` for icons, `/20` for subtle borders. Borders between card sections use `border-base-300/40`.

### Core Components
- `<.table>` — Responsive table (cards on mobile via CSS). Nest inside a content card with `<div class="p-0">`.
- `<.empty_state>` — Dashed border placeholder with icon, title, and optional CTA slot.
- `<.button>` — Use `variant="primary"` for primary actions. Add heroicon before text for clarity.
- Status badges: Use `badge` + color variant + `gap-1.5 capitalize` with a dot indicator (`size-1.5 rounded-full`).

### Modals
The `<.modal>` component has `p-0` on the modal box — content MUST provide its own padding. Never use `<.header>` inside modals. Follow this structure:

```heex
<.modal id="my-modal" show on_cancel={JS.patch(@return_path)}>
  <%!-- Header: icon + title + subtitle + close button --%>
  <div class="flex items-center justify-between border-b border-base-300/40 px-5 py-4">
    <div class="flex items-center gap-3">
      <div class="flex size-9 items-center justify-center rounded-lg bg-primary/10">
        <.icon name="hero-some-icon-mini" class="size-4.5 text-primary" />
      </div>
      <div>
        <h3 class="text-sm font-semibold text-base-content">Title</h3>
        <p class="text-xs text-base-content/40">Subtitle text</p>
      </div>
    </div>
    <button
      phx-click={JS.exec("data-cancel", to: "#my-modal")}
      type="button"
      class="btn btn-sm btn-circle btn-ghost text-base-content/40 hover:text-base-content"
      aria-label="close"
    >
      <.icon name="hero-x-mark" class="size-4" />
    </button>
  </div>
  <%!-- Body --%>
  <div class="px-5 py-5">
    <%!-- Form or content here --%>
  </div>
</.modal>
```

Key rules:
- Header: `px-5 py-4` with `border-b border-base-300/40`
- Body: `px-5 py-5`
- Always include a close button (`btn btn-sm btn-circle btn-ghost`)
- Use an icon in the header with `bg-primary/10` wrapper
- For wider modals, pass `box_class` with `max-w-2xl` (default is `max-w-md`)

### Bulk Action Toolbar
For tables that support multi-select, use this pattern (reference: `LeadsLive`):

1. **Selection state**: Track `selected_ids` as `MapSet.t()` in assigns. Reset to empty in `handle_params/3`.
2. **Checkbox column**: Use the `<.table>` component's `:leading_col` slot. Pass `:header` for the header row and the row item for body rows. The header checkbox supports checked/indeterminate states.
3. **Toolbar**: Render between the filter form and results header, only when selection is non-empty. Shows count, "Clear" link (`clear-selection` event), and action button(s).
4. **Styling**: `border-b border-base-300/40 px-5 py-2.5`, small text. Action buttons use `bg-error/10 text-error` for destructive actions.
5. **Events**: `toggle-select`, `toggle-select-all`, `clear-selection`, `bulk-<action>`. All bulk actions should use `data-confirm`.
6. **Page IDs**: Track `page_lead_ids` in `refresh_leads/1` for select-all logic (don't access stream internals).

### Breadcrumbs
Every dashboard LiveView MUST assign `:breadcrumbs` in each `apply_action/3` clause (or in `mount/3` if there's no `handle_params`). The dashboard layout renders breadcrumbs in the top bar when assigned, falling back to `page_title` if not.

**Data structure:** A list of maps with `:label` (required) and `:to` (optional path). The last item is the current page and should NOT have a `:to` key.

```elixir
# Index action — current page only
assign(socket, :breadcrumbs, [%{label: "Orders"}])

# New/Edit actions — parent link(s) + current page
assign(socket, :breadcrumbs, [
  %{label: "Companies", to: ~p"/dashboard/accounts/#{account.slug}/companies"},
  %{label: company.name, to: ~p"/dashboard/accounts/#{account.slug}/companies/#{company.id}/orders"},
  %{label: "New Order"}
])
```

**Rules:**
- Always set breadcrumbs in every action — `:index`, `:new`, `:edit`, etc.
- Use `~p` sigil for all paths
- Last breadcrumb = current page (no `:to`)
- All parent items must have `:to` links
- For nested resources, include each level (e.g. Companies > Company Name > Orders > New Order)

## Mix Task Structure for Production Compatibility

**IMPORTANT**: All Mix tasks MUST be structured to work in production releases where Mix is not available.

### Required Structure:
1. **Mix Task Module** (`lib/mix/tasks/`) - Only handles CLI arguments/options parsing and delegates to business logic
2. **Business Logic Module** (`lib/lead_router/`) - Contains all implementation logic and can be called directly
