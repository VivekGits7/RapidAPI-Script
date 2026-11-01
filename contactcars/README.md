# ContactCars top-100 dump

The client asked for the cars people actually drive in Egypt. We used ContactCars, the
biggest Egyptian car listing site, as the reference: 8,983 cars for sale across 880
models, counted on 2026-10-30.

## Files

**coverage_report.csv** is one row per ContactCars model, most listed first. It shows
how many of that model's 2000 to 2025 car generations are already in our catalog, which
ones are missing, and how many are queued in the targets file. This is the state before
the top-100 run.

| status | meaning |
|---|---|
| covered | every 2000 to 2025 generation is in the DB |
| partly covered | some generations are in, some are missing |
| missing | none are in |
| not in RapidAPI | the API does not have this model, see the note column |
| no 2000-2025 car model | the API only has it as older or commercial models |

**top100_dump_targets.csv** is the import file. It holds the 354 missing API models
behind the 100 most listed ContactCars models. China and US builds of a car the main make
already has, like TOYOTA (FAW) Corolla or FORD USA Focus, are left out because Egypt
drives the main version. `priority` is the ContactCars rank, so
the dump does the most popular cars first. The ContactCars columns are only there so a
person can read it; the import uses the tec_* ids and priority.

## Running it

```bash
guvrun -m dumper.cli import-targets --csv contactcars/top100_dump_targets.csv --vehicle-type pc
guvrun -m dumper.cli run --vehicle-type pc
guvrun -m dumper.cli counts --vehicle-type pc   # targets done and left, calls used this month
guvrun -m dumper.cli status --vehicle-type pc   # the running job
```

What is done and what is left lives in `rapid_api_dump_targets.status`: pending,
resumable or complete. Each model crawls its newest 6 petrol, hybrid or electric
versions built 2000 to 2025, with same-engine repeats skipped. Expect roughly 820k API
calls for the whole list.
