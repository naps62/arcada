# Arcada

**O Diário da República em linguagem simples.**

Arcada reads the *Diário da República, Série I* (Portugal's official journal) every day and turns each act into a plain-language summary that answers one question: *what changed, for whom, and from when* — with article-level citations back to the official source.

Live at **[arcada.naps.pt](https://arcada.naps.pt)**.

## How it works

- **Scrape** the daily Série I.
- **Classify** each act by life-domain.
- **Summarize** it in plain Portuguese with an LLM, keeping citations to the source articles.
- **Publish** to a searchable register, filtered to each reader's profile.

Arcada is a **signpost, not an authority**: it links to the official text and never poses as legal advice.

## Stack

Elixir · Phoenix / LiveView · PostgreSQL · Oban. Local LLM (llama.cpp) for summarization.

## Development

```sh
mix setup          # install deps, create + migrate DB, build assets
mix phx.server     # serve at http://localhost:4000
mix test           # run tests
```

Requires Elixir/OTP (see `mix.exs`) and PostgreSQL.

## License

[GNU AGPL-3.0-only](LICENSE). Copyright © 2026 Miguel Palhas.

You may use, modify, and self-host Arcada freely. If you run a modified version as a network
service, the AGPL requires you to offer that version's source to its users.

Summaries published by Arcada are derived from the *Diário da República*, whose official text is
the sole authoritative source. Arcada is a signpost, not an authority, and is provided without
warranty of any kind.
