# Polls vs. Cash

A daily tracker of the **wedge** between prediction-market prices and poll-implied
win probabilities. Markets above polls = hope. Markets below polls = doubt.

The whole thing runs free on GitHub: a scheduled Action pulls market prices every
morning, writes `docs/data.json`, and GitHub Pages serves the site. Your WordPress
page just embeds it in an iframe.

```
pipeline/races.csv       <- which markets to track (you edit this)
pipeline/polls.csv       <- poll benchmarks (you update weekly)
pipeline/update_data.R   <- the daily script (R, jsonlite only)
docs/index.html          <- the website (no build step)
docs/data.json           <- the data the site reads (auto-updated)
.github/workflows/update.yml  <- the daily schedule
```

---

## One-time setup (~20 minutes)

### 1. Create the repo
1. Log in to github.com → top right **+** → **New repository**.
2. Name it `pollsvscash` (this becomes part of your URL). Set it **Public**
   (Pages is free only on public repos). Don't add a README. **Create.**
3. On the empty-repo page, click **uploading an existing file** and drag in the
   entire contents of this folder (keep the folder structure — easiest is to
   drag the unzipped folders `pipeline`, `docs`, and `.github` plus this README).
   Commit to `main`.

   *Note: some browsers won't upload the hidden `.github` folder by drag-and-drop.
   If `.github/workflows/update.yml` is missing after upload, create it by hand:
   **Add file → Create new file**, type `.github/workflows/update.yml` as the
   name, and paste the file's contents in.*

### 2. Turn on the website (GitHub Pages)
1. In the repo: **Settings → Pages**.
2. Under "Build and deployment": Source = **Deploy from a branch**,
   Branch = **main**, Folder = **/docs**. Save.
3. After a minute or two your site is live at
   `https://YOURUSERNAME.github.io/pollsvscash/` — open it. You should see the
   board with demo data. (This is not "another website" you maintain — it's just
   free hosting for one page.)

### 3. Let the robot commit
1. **Settings → Actions → General → Workflow permissions** →
   select **Read and write permissions**. Save.
2. Go to the **Actions** tab → "Update Polls vs. Cash data" → **Run workflow**
   to test it manually. Green check = the pipeline ran and committed fresh data.
   (It will fail sensibly until you've put real market IDs in `races.csv` —
   see next step — because the placeholders aren't real markets.)

### 4. Point it at real markets
Edit `pipeline/races.csv` (in GitHub: open the file → pencil icon):

- **Polymarket**: open the market page in your browser. The slug is the last bit
  of the URL, e.g. `polymarket.com/event/.../will-republicans-win-the-senate` →
  slug is `will-republicans-win-the-senate`. Put `polymarket` in `source`, the
  slug in `identifier`, and the outcome name (usually `Yes`) in `outcome`.
- **Kalshi**: each market has a ticker (shown on the market page / in the URL),
  e.g. something like `SENATEPA-26`. Put `kalshi` in `source` and the ticker in
  `identifier`. `outcome` is `yes` or `no`.

Sanity-check a fetch by running the workflow manually (Actions tab) and looking
at the log output, or run `Rscript pipeline/update_data.R` locally.

### 5. Set the poll benchmarks
Edit `pipeline/polls.csv`. For each race id, fill **one** of:
- `poll_prob` — a probability (0–100) straight from a model or your own judgment
  of the polling average, or
- `poll_margin` — the polling margin in points for the side the market is about;
  the script converts it to a probability with a probit using sigma = 5.5 points
  of historical state-poll error.

Update this weekly-ish. Markets update themselves daily; polls barely move
day to day, so a hand-maintained CSV is the honest v1.

### 6. Embed in WordPress
1. In WordPress, create/edit a page → add a **Custom HTML** block.
2. Paste:

```html
<iframe
  src="https://YOURUSERNAME.github.io/pollsvscash/"
  style="width:100%; height:1400px; border:0;"
  title="Polls vs. Cash"
  loading="lazy"></iframe>
```

3. Adjust the `height` until nothing important is cut off (the page doesn't
   auto-size an iframe; 1300–1600px usually covers it). On WordPress.com you
   need the plan tier that allows Custom HTML; self-hosted WordPress allows it
   out of the box.

That's it. From now on the only recurring task is updating `polls.csv` and
occasionally adding/retiring races in `races.csv` — both editable in the
browser on github.com.

---

## Day-to-day

- **The Action runs at 06:30 UTC daily.** It fetches prices, appends the day to
  each race's history (kept to 365 days), and commits `docs/data.json`. If a
  fetch fails it carries forward yesterday's price and notes a WARN in the log.
- **Add a race**: one row in `races.csv`, one row in `polls.csv`. It appears on
  the site after the next run (or trigger one manually from the Actions tab).
- **When a race resolves**: leave its row in `races.csv`. The market price goes
  to ~0 or ~100 and the race stays on the board with its history — that's your
  public track record of whether "hope" or "doubt" was right. Only delete a row
  if it was added by mistake (history lives on in git either way).

## Caveats worth keeping in the methodology note

- The wedge conflates trader bias with genuine information polls miss. That
  ambiguity is the fun of it, but say so on the page (the site's methodology
  section already does).
- Polymarket/Kalshi API shapes occasionally change; if the Action starts
  failing, the log will show which fetch broke.
- Prices are last-trade/mid prices, not liquidity-weighted; thin markets can
  show silly numbers. Prefer headline contracts with real volume.
