# DRE endpoint recon (issue #3) — COMPLETE

> All three target endpoints reverse-engineered **and confirmed end-to-end with a pure
> HTTP client** (no browser needed in production). The OutSystems SPA was driven once in a
> headless Chromium to capture the exact request envelopes; everything below replays with
> plain `Req`/curl. Capture scripts: `/tmp/.../capture*.js` (throwaway).

## Site shape

- `diariodarepublica.pt` is an **OutSystems Reactive (React) SPA**. Every route returns a
  ~2.3 KB bootstrap shell; **no SSR**. App module: **`dr`**.
- All data comes from **`screenservices`** POST endpoints:
  `/dr/screenservices/<Module>/<Screen>/<DataAction>`.
- Official PDFs on `files.diariodarepublica.pt` are **open** (no auth) — the stable
  citation + full-text fallback. `data.dre.pt/eli/...` is just a redirect back into the
  SPA (a stable identifier, **not** a separate API).

## Session + request contract (confirmed)

1. **Cookies/CSRF:** POST any screenservices path once (even `{}`); the response sets
   `nr1Users` + `nr2Users`. URL-decode `nr2Users`, take the **`crf`** field → send it as
   header **`X-CSRFToken`** on every call. Reuse the cookie jar.
2. **Version tokens:**
   - `moduleVersion`: `GET /dr/moduleservices/moduleversioninfo` → `{"versionToken":"…"}`
     (currently `lsbpmahlas4g2WWC0IKDXA`; rotates on DRE deploy).
   - `apiVersion`: per data-action; the 3rd arg of `callDataAction(...)` in each screen's
     `*.mvc.js`. (Hashes below; re-derive on version change.)
3. **Envelope (this was the crux):** data actions take **`screenData.variables`** +
   **`clientVariables`**, *not* a flat `inputParameters`. Sending `inputParameters` yields
   `"No role validation found"`. `clientVariables.Session_GUID` can be a **self-generated
   UUID** — no server-side bootstrap required.

```http
POST /dr/screenservices/<Module>/<Screen>/<DataAction>
Content-Type: application/json; charset=UTF-8
X-CSRFToken: <crf from nr2Users>
X-Requested-With: XMLHttpRequest

{"versionInfo":{"moduleVersion":"<token>","apiVersion":"<hash>"},
 "viewName":"<Screen view>",
 "screenData":{"variables":{ <inputs + their _<x>DataFetchStatus:1 flags> }},
 "clientVariables":{ "Session_GUID":"<uuid>", "Data":"<YYYY-MM-DD>", ... }}
```
Response: `{"versionInfo":{...},"data":{...},"exception":null}`.

## The pipeline (all confirmed against 2026-06-24, DR n.º 120/2026 Série I)

### 1+2 — Editions + their acts for a day  ⟶ one call
`POST /dr/screenservices/dr/Home/WB_Serie1_List/DataActionGetDataAndApplicationSettings`
apiVersion `1ZNbiINloOPj8IhEJxM3QA`, `viewName:"Home.home"`.
Input variables: `DataSelecionada` (`YYYY-MM-DD`), `IsSumarioCompleto:false`,
`IsPageTracked:false` (+ matching `_…DataFetchStatus:1`).
Returns `data.DiarioByDiaList.List[]` — each edition:
`Title`, `DiarioRepublicaId` (DbId), `Numero` (`120`), `DataPublicacao`, and
`DiplomaLegiList.List[]` of acts. Each **act**:
`DbId`, `Numero` (`84/2026`), `Emissor` (`Presidência da República`),
`ConteudoTitle` (`Decreto do Presidente da República n.º 84/2026`),
`Sumario` (HTML), **`LinkSitemap`** = exact detail path
(`/dr/detalhe/decreto-presidente-republica/84-2026-1138160247`).
→ This single call already yields the register skeleton (edition + acts + sumário).

Alt edition lister (Elasticsearch hits, both séries): `Home/home/DataActionGetDRByDataCalendario`
(apiVersion `A00rktBtkSvxDLsFy+6mgg`) → `dbId`, `numero`, `conteudoTitle`
(`…Série I de 2026-06-24`), per-série bucket counts. Useful to detect *whether* Série I
published on a date.

### Edition detail (acts list with canonical links)
`POST …/dr/Legislacao_Conteudos/Conteudo_Det_Diario/DataActionGetDadosAndApplicationSettings`
apiVersion `r2HCK_WYkdDO5ao7yWPCBw`, `viewName:"Legislacao_Conteudos.Conteudo_Det_Diario"`.
Inputs: `Tipo:"diario-republica"`, `Key:"120-2026-1138160245"`.
Returns the acts each with `LinkSitemap` (authoritative slug+key — prefer over
reconstructing). Companion actions on same screen: `DataActionGetLinks`
(`CgO+rxO79iS7v+IeXgUgxw`), `GetPaginacaoValues` (`xbenG1hrOTlPoYfQvRA_Iw`),
`GetSyncInfo` (`XE4_yYFKxcznnEi1ZhyszA`).

### 3 — Act detail / full text + PDF
`POST …/dr/Legislacao_Conteudos/Conteudo_Detalhe/DataActionGetAllConteudoDetalheData`
apiVersion `f6iEozloG7S5uAiM9ydqeQ`, `viewName:"Legislacao_Conteudos.Conteudo_Detalhe"`.
Inputs: `Tipo` (slug) + `Key` (`<numero>-<year>-<dbid>`) — both taken straight from the
act's `LinkSitemap`. Returns `data.…DetalheConteudo`:
`Titulo`, `Numero`, `Emissor`/`EmissorAcronimo` (`PR`), `TipoDiploma`/`…Acronimo`
(`decpresrep`), `Serie` (`I`), `Sumario` (**plain text**), `Texto` + `TextoFormatado`
(full text, HTML), `DataPublicacao`, `Pagina`, **`URL_PDF`**, **`ELI`**.
(Helpers on screen: `GetURLInfo` `0Xe1Eq968Dp8zCmSEuAfyg`, `GetEmissoresAndPartes`
`78jRreiPPaBOPlsMQZf5Fg`.)

Example resolved artifacts:
- `URL_PDF` → `https://files.diariodarepublica.pt/1s/2026/06/12000/0000300003.pdf` (open, 200).
- `ELI` → `https://data.dre.pt/eli/decpresrep/84/2026/06/24/p/dre/pt/html`.

### Key/slug rules
- `Key = "<Numero with '/'→'-'>" + "-" + <DbId>` (e.g. `84/2026` + `1138160247` →
  `84-2026-1138160247`). Edition uses its own number+DbId.
- `Tipo` slug from `convertTipoDiploma` (e.g. `decreto-presidente-republica`). **Don't
  reconstruct** — read `LinkSitemap` from the list/edition response and split it.

## Recommended scraper recipe (for issue #4)

1. Bootstrap session: POST `{}` once → grab cookies + `crf`; GET `moduleversioninfo` →
   `moduleVersion`; self-gen `Session_GUID`.
2. For date `D`: call **WB_Serie1_List** (`DataSelecionada=D`). If no Série I edition,
   skip (use `GetDRByDataCalendario` série buckets to check cheaply).
3. Upsert editions; upsert acts by **`DbId`** (unique) from `DiplomaLegiList`, storing
   `Numero`, `Emissor`, `ConteudoTitle`, `Sumario`, `LinkSitemap`.
4. Per act: split `LinkSitemap` → `Tipo`,`Key` → **GetAllConteudoDetalheData** for
   `Texto`/`TextoFormatado`, `URL_PDF`, `ELI`, `Pagina`. Fetch the PDF as the citation
   artifact / full-text fallback.
5. Tolerant parsing + re-derive `moduleVersion`/`apiVersion` on a version-changed flag so
   the scraper survives DRE redeploys. Idempotent on re-run.

## Self-healing apiVersion re-derivation (issue #14 — DONE)

The scraper re-derives a rotated `apiVersion` at runtime, over **plain HTTP** (no
browser). When a data-action responds `versionInfo.hasApiVersionChanged: true`,
`Arcada.Scraper.Client` re-derives the current hash, swaps it into the client,
and retries the call once — surviving DRE redeploys with no config edit. The
threaded client means the fresh hash is reused for the rest of the run.

Derivation (`Arcada.Scraper.ApiVersionResolver`):
1. `GET /dr/moduleservices/moduleinfo` → `manifest.urlVersions`: every asset path
   (incl. each screen's `*.mvc.js`) mapped to its rotating `?<hash>` suffix. This
   is the piece that made **option 1** (static mvc.js parse) viable — the hashed
   script URL is discoverable without running the OutSystems manifest loader.
2. `GET /dr/scripts/<Module>.<Screen>.mvc.js?<hash>` → the screen bundle.
3. Extract the 3rd arg of the target `callDataAction("<Action>", "<path>",
   "<apiVersion>", …)`.

The hashes below are still the compile-time defaults (last-known-good); they're
now just the seed/fallback if re-derivation ever fails.

## apiVersion hash table (re-derive on deploy)
| action | apiVersion |
|---|---|
| Home/WB_Serie1_List/DataActionGetDataAndApplicationSettings | `1ZNbiINloOPj8IhEJxM3QA` |
| Home/home/DataActionGetDRByDataCalendario | `A00rktBtkSvxDLsFy+6mgg` |
| Legislacao_Conteudos/Conteudo_Det_Diario/DataActionGetDadosAndApplicationSettings | `r2HCK_WYkdDO5ao7yWPCBw` |
| Legislacao_Conteudos/Conteudo_Detalhe/DataActionGetAllConteudoDetalheData | `f6iEozloG7S5uAiM9ydqeQ` |
| Legislacao_Conteudos/Conteudo_Detalhe/DataActionGetURLInfo | `0Xe1Eq968Dp8zCmSEuAfyg` |

> `moduleVersion` and all `apiVersion` hashes change on each DRE deployment. The scraper
> must re-derive them (steps 2/3 above), never hard-code long-term.
