# DRE endpoint recon (issue #3)

> Reverse-engineering of `diariodarepublica.pt` ingestion endpoints. Status: **endpoint
> catalog + auth mechanism confirmed via HTTP; live response shapes still need a browser
> capture** (see [Blocker](#blocker)).

## Summary of the site

- `diariodarepublica.pt` is an **OutSystems Reactive (React) SPA**. Every route
  (`/dr/home`, `/dr/detalhe/...`) returns the same ~2.3 KB bootstrap shell; **no SSR**.
- App module: **`dr`** (`environmentName: "DRE Production"`, OutSystems).
- All data is fetched at runtime via **`screenservices`** POST endpoints
  (`/dr/screenservices/<Module>/<Screen>/<DataAction>`).
- **No official API.** PDFs under `files.diariodarepublica.pt` are the stable
  citation/fallback artifact.

## How the SPA discovers its endpoints (for the scraper)

1. `GET /dr/moduleservices/moduleversioninfo` → `{"versionToken":"<hash>"}`.
   This is the **`moduleVersion`** sent in every data-action request. Rotates on deploy.
2. `GET /dr/moduleservices/moduleinfo` → JSON `{manifest, data}`.
   - `manifest.urlVersions` — map of every JS module → versioned URL (498 entries).
   - `manifest.urlMappings` — route → `index.html` (24 routes; all SPA-served).
3. Per-screen module JS (e.g. `dr.Home.WB_Serie1_List.mvc.js`) contains the
   `callDataAction(name, url, apiVersion, ...)` calls. The **3rd arg is the per-action
   `apiVersion`** hash sent alongside `moduleVersion`.

A robust scraper re-derives `moduleVersion` + `apiVersion` from steps 1–3 rather than
hard-coding them, so it survives DRE redeploys.

## Auth / anti-CSRF mechanism (confirmed)

- First request to any `screenservices` path sets two cookies:
  - `nr1Users` — anonymous session.
  - `nr2Users=crf%3d<TOKEN>%3buid%3d0%3bunm%3d` — the **`crf`** field (URL-decoded) is
    the CSRF token.
- Every data-action POST must send that token as header **`X-CSRFToken: <crf>`** plus the
  cookies. Confirmed working: the server accepts the token and version info
  (`hasModuleVersionChanged:false`, `hasApiVersionChanged:false`).

### Request envelope (OutSystems data action)

```
POST /dr/screenservices/<Module>/<Screen>/<DataAction>
Content-Type: application/json; charset=UTF-8
X-CSRFToken: <crf from nr2Users cookie>
X-Requested-With: XMLHttpRequest

{"versionInfo":{"moduleVersion":"<versionToken>","apiVersion":"<action hash>"},
 "inputParameters":{ ... }}
```

Response envelope:
```json
{"versionInfo":{"hasModuleVersionChanged":false,"hasApiVersionChanged":false},
 "data":{ ... },"exception":null}
```

## The three target endpoints

### 1. List Série I editions for a day
- **URL:** `/dr/screenservices/dr/Home/WB_Serie1_List/DataActionGetDataAndApplicationSettings`
- **apiVersion:** `1ZNbiINloOPj8IhEJxM3QA`
- **Input:** `DataSelecionada` (Date, `YYYY-MM-DD`); also accepts `IsSumarioCompleto`,
  `IsSuplemento` (bool).
- **Returns (from JS):** `diarioByDiaListOut` (the day's diários/editions) +
  `environmentNameOut`.
- Related: `WB_Serie1_List/ActionFriendlyURL` builds the public URL as
  `friendlyURL("serie-1", <date>, ...)`.

### 2. Sumário → acts for an edition (diário detail)
- **Screen:** `Legislacao_Conteudos/Conteudo_Det_Diario`. Data actions:
  - `DataActionGetDadosAndApplicationSettings` — apiVersion `r2HCK_WYkdDO5ao7yWPCBw` (main payload: edition + its acts)
  - `DataActionGetLinks` — `CgO+rxO79iS7v+IeXgUgxw`
  - `DataActionGetPaginacaoValues` — `xbenG1hrOTlPoYfQvRA_Iw`
  - `DataActionGetSyncInfo` — `XE4_yYFKxcznnEi1ZhyszA`
- Sumário HTML rendered via `Legislacao_Conteudos/SumarioHTML` screen.
- **Input:** edition id (from the list in #1). Exact param name TBD in browser capture.

### 3. Act / diploma detail + full text
- **Screen:** `Legislacao_Conteudos/Conteudo_Det_Diploma` (full diploma view) and
  `Conteudo_Detalhe`. PDF + source URLs assembled by the shared controller actions
  `ActionIteratingGetPDFURLForDRorDL`, `ActionGetFullURL`
  (`/dr/screenservices/dr/<Action>`).
- **Input:** diploma id (from #2). Exact param names + the GetPDFURL contract TBD in
  browser capture.

## PDF / citation artifact
- `files.diariodarepublica.pt` hosts the official PDFs (stable citation/fallback).
- Exact path is produced server-side by `ActionIteratingGetPDFURLForDRorDL` /
  `ActionGetFullURL`; needs a real diploma id to confirm the pattern. Blind path guesses
  301 to `/dr/error`.

## Blocker

Replaying the data actions over plain HTTP returns:
```json
{"exception":{"specificType":"System.InvalidOperationException",
              "message":"No role validation found"}}
```
…for **every** input/envelope variant. Version tokens and CSRF are accepted, so this is a
**server-side role/session gate** that the SPA establishes via a bootstrap step on first
real screen load (anonymous-role assignment keyed to the session). A synthetic
cookie-only session doesn't carry it.

**Next step (the plan's intended method):** drive the live site once in a browser with
DevTools open and capture, for a real edition + diploma:
1. any bootstrap/role call that precedes the first data action,
2. the exact request bodies (input param names) for endpoints #2 and #3,
3. the real response JSON shapes (so we can map them to `editions`/`acts`),
4. the resolved `files.diariodarepublica.pt` PDF URL.

Then replay with Req in the scraper (issue #4). Requires the Claude Chrome extension to be
connected (it was not, this session), or a manual HAR capture.

## Confirmed facts (replayable now)
- Module version: `GET /dr/moduleservices/moduleversioninfo`.
- CSRF: read `crf` from `nr2Users` cookie → send as `X-CSRFToken`.
- Endpoint URLs + apiVersion hashes above.
- Série I input param: `DataSelecionada` (`YYYY-MM-DD`).
