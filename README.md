# Home Assistant OSM Tile Renderer Add-on

One-shot job that imports an OpenStreetMap extract and pre-renders ("seeds") every
map tile in a configurable radius around a point, so they can be served **statically**
afterwards with no live rendering and no dependency on any third-party tile API.

Pairs with [osm-tile-server](https://github.com/override80/homeassistant-osm-tile-server-addon),
which serves the cache this add-on produces.

## Why this exists

A `custom:map-card` (or the native HA map) pointed at `tile.openstreetmap.org` is fine for
light use, but bulk pre-caching an area by hammering OSM's public tile servers violates
their [Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/) (which
explicitly forbids bulk downloading) and risks an IP ban. Commercial providers like
MapTiler/Mapbox avoid that problem but have monthly request quotas that a one-time
pre-cache of tens of thousands of tiles can burn through on its own.

This add-on sidesteps both problems: it imports an OSM data extract you already
downloaded once, and renders tiles locally with your own Mapnik/renderd stack
([Overv/openstreetmap-tile-server](https://github.com/Overv/openstreetmap-tile-server)) --
no ongoing API calls, no quotas, no ToS issue, at the cost of one CPU-heavy pass
that only needs to run again if you want to extend the area or refresh the data.

## Configuration

```yaml
pbf_url: ""                  # e.g. a Geofabrik/BBBike download URL (see below)
home_latitude: 45.8312046
home_longitude: 8.7331394
radius_km: 50
min_zoom: 10
max_zoom: 17
threads: 4
```

- `pbf_url`: direct download URL for an `.osm.pbf` extract covering your radius. Leave
  empty and instead place the file yourself at `/share/osm-tiles/region.osm.pbf` if you'd
  rather generate a precise custom extract -- **a 50km radius often straddles the boundary
  between two country/region extracts** (e.g. Switzerland vs. Italy), so a custom bbox
  extract from [extract.bbbike.org](https://extract.bbbike.org/) covering exactly your
  area is usually cleaner than picking one country's Geofabrik file and missing a corner
  of your radius.
- `home_latitude` / `home_longitude`: center point (defaults to this install's
  `zone.home`).
- `radius_km`: how far out to seed tiles from the center point.
- `min_zoom` / `max_zoom`: zoom levels to pre-render. 10-17 covers overview down to
  street-level detail without the building-level tiles of z18+, which multiply the tile
  count roughly 4x per extra zoom level.
- `threads`: parallel render threads (and osm2pgsql import processes).

## What it does

1. Downloads `pbf_url` (if set and not already present) to `/share/osm-tiles/region.osm.pbf`.
2. Imports it into a local PostGIS database under `/share/osm-tiles/database` (skipped on
   subsequent runs if already imported).
3. Starts postgres + renderd long enough to run `render_list`, seeding every tile in the
   configured bbox/zoom range into `/share/osm-tiles/tiles`.
4. Touches `/share/osm-tiles/seed-complete` and stops.

All of this lives under `/share/osm-tiles`, not this add-on's private `/data`, specifically
so the `osm-tile-server` add-on (a separate container) can read the exact same database and
tile cache afterwards.

## Resource cost

The import + seed pass is genuinely heavy: PostGIS import of a regional extract plus
Mapnik rendering of tens of thousands of tiles can take a few hours of sustained CPU and a
few GB of RAM/disk, depending on extract size and zoom range. Run it when the host is
otherwise idle. Steady-state cost after it finishes is zero -- this add-on isn't meant to
stay running; stop it once "Seeding complete" appears in the log.

Re-running is idempotent: it skips the import if `/share/osm-tiles/database` is already
populated, so widening `max_zoom` later only re-seeds the new zoom levels' worth of tiles,
not the whole import.

## License

MIT, see `LICENSE`. Wraps [Overv/openstreetmap-tile-server](https://github.com/Overv/openstreetmap-tile-server)
(also MIT), which itself bundles [openstreetmap-carto](https://github.com/gravitystorm/openstreetmap-carto).
