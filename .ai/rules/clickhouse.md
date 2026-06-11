# ClickHouse doctrine + ch-go style

## Table topology

- **Few canonical ingestion tables** storing raw data unchanged, exactly as received. No derivation at ingest. The ingestion table is also the debugging ground truth — when investigating what actually arrived, query it directly; no separate raw-copy tables.
- **Aggregation tables only when needed, as general building blocks** (latest, hourly/daily states, events timeline) — each serves many queries, never one table per endpoint/query.
- **Split aggregate tables by aggregation kind**: a median-type table, a sum-type table, an events-timeline table. One wide table carrying every aggregate kind as columns (count/sum/min/max/median-state/first/last/events on one row) gets heavy — many columns, few used per query. Narrow tables stay cheap.
- **Materialized views: always `TO <explicit external table>`, never engine-internal storage. Always `FROM` an original ingestion table — never MV-on-MV cascading.** Fan-out (many MVs from one source) and fan-in (many MVs to one target) are both fine.
- Keep MV bodies trivial; transformation can live in the target table's EPHEMERAL + MATERIALIZED columns so backfill ≡ `INSERT SELECT` of raw columns.

## Deduplication & engines

- **Dedup at insert time, not at merge time.** MV aggregations see raw inserted blocks; ReplacingMergeTree dedups later at merge, so aggregates count duplicates. Prefer atomic `INSERT INTO ... SELECT ... FROM <external table>` filtering out rows already present. Inserts mostly carry one or a few devices, so the existence check is cheap.
- With insert-time dedup, duplicates stop being a concern downstream: aggregations simplify, and plain static hourly/daily (and coarser) aggregate tables beat Replacing+aggregate-state machinery.
- ReplacingMergeTree is still fine for an ingestion table where occasional dups are tolerable; `FINAL` on every read of it. Plain MergeTree for append-only logs. AggregatingMergeTree for state tables.
- **ORDER BY: entity before type**: `(device, type, ..., ts)`. Type has lower cardinality, but real queries ask "a few types for a set of devices", almost never "all devices for one type". Time last. PARTITION BY coarse: month for raw, year for compacted.

## TTL (load-critical)

- **Never `TTL ts + INTERVAL ...` raw** — it produces newly-expired rows every second and generates enormous background merge load. Truncate the TTL trigger to hour or day boundaries: `TTL toStartOfHour(ts) + INTERVAL ...` / `toStartOfDay(...)`.
- Shift TTL phases across tables (one expires at 00h, the next at 01h, the next at 02h) so expiration work doesn't stack.
- TTL `GROUP BY` rollup: **every column not in GROUP BY gets an explicit, correct SET aggregator** (including MATERIALIZED and Nested sub-columns). Missing or wrong aggregators fail at MERGE time, not CREATE time → merged parts never commit → parts accumulate → TOO_MANY_PARTS. Verify each aggregator computes what you mean: `min(val_max)` type-checks and is wrong.

## Column conventions

- `ts DateTime64(9)` — 9 digits almost always, maps to Go's UnixNano. Preserve source precision. `time DateTime ALIAS ts` for quick manual queries. When the natural column is named differently, restore the convention with an alias chain (`start_ts` → `start_time ALIAS start_ts` → `time ALIAS start_time`). Same for `server_ts`/`server_time`.
- ALIAS bucket ladder on time-series tables: `minute`, `hour`, `day`, `week`, `month` (toStartOf*). Manual queries then say `WHERE day = ...`.
- Useful footer columns: `_insert_time DateTime('UTC') MATERIALIZED now()`, minmax skip index on server time, `CONSTRAINT ... CHECK` rejecting obvious garbage (notEmpty ids, nonzero times).
- Types: `LowCardinality(String)` for open enums; real `Enum8` for closed sets; `(Simple)AggregateFunction` states where state tables are warranted; `Dynamic` only at the JSON projection edge.

## json_ingest pattern

- One global funnel: `json_ingest(table String, json String, arg1 String, _insert_time ...)`, plain MergeTree. Per-target MV filters `WHERE table = 'x'` and parses with typed `JSONExtract`. `arg1` is the out-of-band blob slot so the JSON stays a clean struct marshal.
- Go side is just `json.Marshal` of the event struct — schema evolution lives in the SQL MV, no Go column plumbing. Use for wide/low-volume tables; high-volume tables get native columnar inserts.
- Companion `x_to_json` functions: each raw table gets a function returning the exact same JSON back, so data round-trips losslessly for export/import/backup.

## Go vs ClickHouse division of labor

- ClickHouse is generally more performant than Go — don't hesitate to push logic into it: JSON marshalling of results, trivial preprocessing, formatting, aggregation. Not everything belongs in the DB, but the default lean is toward SQL.

## ch-go usage (always ch-go, native protocol)

- `chpool.Pool`, ZSTD compression, TLS default with `?insecure` opt-out, config via URL query params.
- **Column buffers are long-lived struct fields, built once, reused forever.** Per-table batch struct holds `proto.Col*` columns + a prebuilt `ch.Query` whose `Input` points at them; `query.Body = query.Input.Into("table")`. LowCardinality/Array wrap backing-buffer fields stored alongside. MATERIALIZED/ALIAS columns are absent from Input — the server computes them.
- Concurrent producers coalesce into ONE insert via `nikand.dev/go/batch`: first writer of a batch does `Input.Reset()` (capacity retained), everyone appends into the shared columns. No commit-delay/throttle inside the batch path — batch coalescing alone is the mechanism; added delays just burn resources.
- ID sets go in as `ch.ExternalTable`s (never IN-list strings); scalars as typed `proto.Parameter` `{name:Type}`. Request DTO fields can BE `proto.ColUUID` so JSON unmarshal lands directly in the wire column.
- Results: never row-scan into structs. Project a single string column `j` of finished JSON; read via `proto.ColStr` + `OnResult` per block, append `RowBytes(i)` to the output buffer. NDJSON for server-to-server, `[...]`-wrapped for browsers.
- Observability: `QueryID = span ID`, OnProgress/OnProfile/OnLogs hooks gated by tlog verbosity topics.

## Query style

- Embedded `.sql` files (`//go:embed`), one per endpoint; string building only when the shape genuinely varies.
- Shape: one flat `WITH` block — named constants/params first, then flat CTE chain, one final JSON projection. Read top-to-bottom, no nested subqueries.
- Idioms: empty external table = "all" (`(SELECT count() == 0 FROM _ids) AS all_ids`); `0` is the universal unset sentinel for times/filters (`(start = 0 OR time >= start)`); inline-alias-in-expression to compute once and reference twice (`(argMax(...) AS x).1, x.2`); named-tuple casts for structured JSON fields; conditional-aggregation pivot (`xxIf(type = '...')`) over per-type subqueries — one scan, many aggregates.
- `argMax(value, ts)` for latest; `argAndMax`/`argAndMin` for the (arg, val) pair; tuple-wrap `argMin((a,b,c), v)` only for 3+ companions; merge combinators on states (`medianMergeIf`).
- Output shaping in SQL, not Go: multi-column row → `formatRowNoNewline('JSONEachRow', *) AS j`; single complete expression → `toJSONString(...)`. Never `toJSONString(tuple(*))` (loses key names). Format-choice UDFs (`timefmt(t, fmt)`) instead of duplicate query variants.
- Tiny named SQL UDFs at the top of schema files for repeated expressions: `r1`, `timefmt`.
- CTE/alias hygiene: CTE names must not shadow real tables; result-column aliases must not shadow aggregate function names (`count`, `sum`, `avg`, ...) — use `v_cnt`, `n_samples`. Equality is `=`.
- Comments explain semantics, not history; candidate optimizations kept as `-- TODO: test if ...`.

## Schema lifecycle

- No migration framework. Schemas are idempotent `CREATE ... IF NOT EXISTS` files embedded in the binary, executed at startup; evolution is convergence, not history.
- Destructive paths are explicit opt-in commands (wipe with hand-maintained DROP/TRUNCATE blocks); each schema file carries its commented DROP header for manual iteration; backfill statements live as comments next to the MV they mirror.
