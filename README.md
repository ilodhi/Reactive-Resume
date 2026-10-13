# Resume Builder (Adam Lodhi)

Privacy-first **web** deployment of [Reactive Resume](https://github.com/reactive-resume/reactive-resume) v6 for [Adam Lodhi](https://github.com/ilodhi).

Use it at your own Vercel URL. Your resumes live in **your** Neon Postgres + private Vercel Blob (+ Upstash Redis for coordination) — not on OpenAI, public S3, or third-party analytics.

> **Windows offline launcher:** abandoned. Old scripts are under [`legacy/windows-launcher/`](./legacy/windows-launcher/) for reference only.

---

## Why this stack

Reactive Resume v6 **officially supports Vercel** (static frontend + Hono backend as Vercel Services). That keeps the full upstream feature set (editor, templates, PDF/DOCX/Markdown/JSON export, cover letters, job tracker, local accounts) without rewriting a Next.js clone.

| Piece | Role |
| --- | --- |
| Vercel Services | Hosts the app (`frontend` CDN + `backend` Node Function) |
| Neon Postgres | Accounts, resumes, letters, applications |
| Vercel Blob (private) | Photos / uploads |
| Upstash Redis | Rate limits, live updates (required on Vercel) |

---

## Privacy guarantees

**What stays in your stack**

- Account data, resume JSON, cover letters, job applications → **your Neon**
- Uploaded pictures/files → **your private Vercel Blob**
- Session cookies → browser ↔ **your Vercel deployment**

**What does *not* leave your stack (when configured as below)**

- No OpenAI / Anthropic / Gemini / OpenRouter calls (leave shared `AI_*` blank; do not add providers in Settings → AI)
- No Google/GitHub/LinkedIn OAuth (leave those client IDs blank)
- No Firecrawl / Tavily / Exa job-search APIs (leave `WEB_ACCESS_*` blank)
- No built-in third-party analytics or ads (upstream design)
- No external S3 — Vercel forces private Blob

**Still required by Vercel (not telemetry)**

- `AUTH_SECRET` — signs your sessions
- `ENCRYPTION_SECRET` — required by the Vercel build; encrypts AI keys *if* anyone adds them later
- Upstash Redis — coordination on serverless; data stays in **your** Upstash DB

Optional SMTP: without it, verification emails go to Function logs (fine for a personal instance).

---

## Deploy to Vercel (Adam’s next click)

### Option A — Deploy button (fastest)

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Filodhi%2FResume-builder&project-name=resume-builder&repository-name=Resume-builder&env=AUTH_SECRET%2CENCRYPTION_SECRET&envDescription=Generate+two+independent+secrets+with+openssl+rand+-hex+32.+Keep+these+across+redeploys.+Leave+AI+and+OAuth+blank+for+privacy.&envLink=https%3A%2F%2Fdocs.rxresu.me%2Fself-hosting%2Fvercel&stores=%5B%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22integrationSlug%22%3A%22neon%22%2C%22productSlug%22%3A%22neon%22%7D%2C%7B%22type%22%3A%22integration%22%2C%22protocol%22%3A%22storage%22%2C%22integrationSlug%22%3A%22upstash%22%2C%22productSlug%22%3A%22upstash-kv%22%7D%2C%7B%22type%22%3A%22blob%22%2C%22access%22%3A%22private%22%7D%5D)

1. Click **Deploy**.
2. Generate two secrets locally and paste them when prompted:

   ```bash
   openssl rand -hex 32   # AUTH_SECRET
   openssl rand -hex 32   # ENCRYPTION_SECRET (different value)
   ```

3. Approve **Neon**, **Upstash**, and **private Blob**.
4. In the Vercel project: **Settings → Build and Deployment → Framework Preset → Services**. Keep the repo root (do **not** set root to `apps/web`). Keep committed `vercel.json`.
5. Deploy. Migrations run during the backend build — you do not run them by hand.
6. Open `https://YOUR-PROJECT.vercel.app/api/health` — `database`, `storage`, and `redis` should be healthy.
7. Open the app URL → create **your** account.
8. (Recommended) Set `FLAG_DISABLE_SIGNUPS=true` in Vercel env and redeploy so only you can register.

### Option B — Existing GitHub repo

1. Import [ilodhi/Resume-builder](https://github.com/ilodhi/Resume-builder) in Vercel.
2. Framework Preset: **Services**.
3. Connect Neon + private Blob + Upstash (Marketplace).
4. Set `AUTH_SECRET` and `ENCRYPTION_SECRET` (Production).
5. Leave blank: all `AI_*`, `WEB_ACCESS_*`, Google/GitHub/LinkedIn OAuth, `S3_*`.
6. Deploy.

Full upstream reference: [Self-hosting on Vercel](https://docs.rxresu.me/self-hosting/vercel).

**Hobby note:** This fork schedules career cron **once daily** (`0 0 * * *`) so it fits Vercel Hobby. Pro can restore minute-level scheduling if you want.

---

## Environment (privacy-first)

See [`.env.example`](./.env.example). Highlights:

| Variable | Personal Vercel setup |
| --- | --- |
| `AUTH_SECRET` | Required — `openssl rand -hex 32` |
| `ENCRYPTION_SECRET` | Required on Vercel — separate secret |
| `DATABASE_URL` / Redis / Blob | Injected by Marketplace |
| `AI_*` / `WEB_ACCESS_*` | **Leave unset** |
| OAuth client IDs | **Leave blank** |
| `S3_*` | **Do not set** on Vercel (Blob only) |
| `FLAG_DISABLE_SIGNUPS` | `true` after you create your account |
| `CRON_SECRET` | Optional; needed if you want `/api/career/run` cron |

Never paste Docker’s S3/local URLs into Vercel — the build will refuse non-Blob storage.

---

## Run locally (Docker)

Needs Docker. Node **24** + pnpm are required for non-Docker source builds.

```bash
git clone https://github.com/ilodhi/Resume-builder.git
cd Resume-builder
cp .env.example .env
# Set AUTH_SECRET and ENCRYPTION_SECRET (openssl rand -hex 32 each)
docker compose up -d --build
# Open http://localhost:3000
```

For source development, follow [Reactive Resume development docs](https://docs.rxresu.me/contributing/development).

---

## Features (upstream Reactive Resume)

Create/edit resumes, templates, live PDF preview, export PDF/Word/Markdown/JSON, cover letters, job application tracker, passkeys/2FA, import JSON Resume / LinkedIn / PDF. Optional AI assistant exists upstream but stays **off** when you leave AI keys empty.

---

## Attribution & license

Based on **Reactive Resume** by Amruth Pillai — [MIT](./LICENSE).  
Upstream: https://github.com/reactive-resume/reactive-resume  
Docs: https://docs.rxresu.me
