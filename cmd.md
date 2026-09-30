## Bus

Bus rows are stored as their own BUS type. RapidAPI only answers bus vehicles and categories on the CV type, so the run calls CV and saves as BUS.

Run BUS: `guvrun -m dumper.cli run --vehicle-type bus`
Run BUS at max speed: `guvrun -m dumper.cli run --vehicle-type bus --workers 12 --rate 22`
Only the 100 bus models never dumped before, add: `--makes 4191,5478,162,2667,2488`

Max speed is 22 calls per second. The MEGA plan cuts off at 25 per second, measured 2026-09-30, and one 429 cools the key for 5 seconds, so going higher is slower.
Check Count: `guvrun -m dumper.cli counts --vehicle-type bus`
Status: `guvrun -m dumper.cli status --vehicle-type bus`
Pause: `guvrun -m dumper.cli stop --vehicle-type bus`
Resume: `guvrun -m dumper.cli resume --vehicle-type bus`

Pause also works with one Ctrl+C in the run terminal, a second Ctrl+C force quits.

## CV

Run CV: `guvrun -m dumper.cli run --vehicle-type cv`
Check Count: `guvrun -m dumper.cli counts --vehicle-type cv`
Pause: `guvrun -m dumper.cli stop --vehicle-type cv`
Resume: `guvrun -m dumper.cli resume --vehicle-type cv`

## Media to S3

S3_ENABLED=true `guvrun media_rapid_to_s3.py`

Handy variants:

`guvrun media_rapid_to_s3.py --target articles`       # one table only
`guvrun media_rapid_to_s3.py --limit 5000`            # cap per target
`guvrun media_rapid_to_s3.py --concurrency 48`        # more in flight
`guvrun media_rapid_to_s3.py --retry-failed`          # re-try the sentinels

guvrun scripts/sync_search_index.py

guvrun backfill_category_links.py
