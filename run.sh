#!/bin/bash
# Imports an OSM extract and pre-renders ("seeds") every tile in a lat/lon radius
# into a tile cache that osm-tile-server later serves statically. Idempotent: safe
# to re-run to extend the zoom range or pick up a refreshed extract.
set -euo pipefail

CONFIG_PATH=/data/options.json

PBF_URL=$(jq -r '.pbf_url // empty' "$CONFIG_PATH")
HOME_LAT=$(jq -r '.home_latitude' "$CONFIG_PATH")
HOME_LON=$(jq -r '.home_longitude' "$CONFIG_PATH")
RADIUS_KM=$(jq -r '.radius_km' "$CONFIG_PATH")
MIN_ZOOM=$(jq -r '.min_zoom' "$CONFIG_PATH")
MAX_ZOOM=$(jq -r '.max_zoom' "$CONFIG_PATH")
THREADS=$(jq -r '.threads' "$CONFIG_PATH")

SHARE_DIR=/share/osm-tiles
mkdir -p "$SHARE_DIR/database" "$SHARE_DIR/style" "$SHARE_DIR/tiles"
# renderd runs as the unprivileged "renderer" user (upstream's own run.sh re-chowns
# the postgres subdirectory to postgres:postgres on every "import"/"run", so this
# broad chown doesn't fight that -- it only matters for style/ and tiles/, which
# renderd and the carto build step need to write as "renderer").
chown -R renderer:renderer "$SHARE_DIR"

# /data itself is a bind mount from Supervisor and can't be replaced, but the
# database/style/tiles directories under it are plain dirs baked into the image --
# redirect those onto /share so osm-tile-server (a separate add-on/container) can
# read the exact same data later.
rm -rf /data/database /data/style /data/tiles
ln -s "$SHARE_DIR/database" /data/database
ln -s "$SHARE_DIR/style" /data/style
ln -s "$SHARE_DIR/tiles" /data/tiles

if [ -n "$PBF_URL" ] && [ ! -f "$SHARE_DIR/region.osm.pbf" ]; then
  echo "=== Downloading OSM extract from ${PBF_URL} ==="
  wget -q --show-progress -O "$SHARE_DIR/region.osm.pbf" "$PBF_URL"
fi

if [ ! -f "$SHARE_DIR/region.osm.pbf" ]; then
  echo "ERROR: no OSM extract found."
  echo "Either set the 'pbf_url' option, or place your own extract manually at"
  echo "${SHARE_DIR}/region.osm.pbf before starting this add-on."
  echo "A 50km radius often straddles country/region extract boundaries -- a custom"
  echo "bbox extract (e.g. from https://extract.bbbike.org/) covering exactly your"
  echo "area avoids having to stitch together multiple country extracts."
  exit 1
fi
ln -sf "$SHARE_DIR/region.osm.pbf" /data/region.osm.pbf

export THREADS

if [ ! -f /data/database/postgres/PG_VERSION ]; then
  echo "=== Importing OSM data into PostGIS (this can take a while) ==="
  /run.sh import
else
  echo "=== Database already imported -- skipping import ==="
  echo "(delete ${SHARE_DIR}/database to force a clean re-import)"
fi

echo "=== Starting renderd/postgres/apache to seed the tile cache ==="
/run.sh run &
SERVER_PID=$!

echo "Waiting for renderd socket..."
for _ in $(seq 1 120); do
  [ -S /run/renderd/renderd.sock ] && break
  sleep 1
done
if [ ! -S /run/renderd/renderd.sock ]; then
  echo "ERROR: renderd never came up"
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

# Bounding box around home_latitude/home_longitude, equirectangular approximation
# (plenty accurate at a 50km scale).
LAT_MIN=$(awk -v lat="$HOME_LAT" -v r="$RADIUS_KM" 'BEGIN{printf "%.6f", lat - r/111.32}')
LAT_MAX=$(awk -v lat="$HOME_LAT" -v r="$RADIUS_KM" 'BEGIN{printf "%.6f", lat + r/111.32}')
LON_MIN=$(awk -v lat="$HOME_LAT" -v lon="$HOME_LON" -v r="$RADIUS_KM" 'BEGIN{pi=atan2(0,-1); rad=lat*pi/180; printf "%.6f", lon - r/(111.32*cos(rad))}')
LON_MAX=$(awk -v lat="$HOME_LAT" -v lon="$HOME_LON" -v r="$RADIUS_KM" 'BEGIN{pi=atan2(0,-1); rad=lat*pi/180; printf "%.6f", lon + r/(111.32*cos(rad))}')

echo "=== Seeding zoom ${MIN_ZOOM}-${MAX_ZOOM} for bbox lat[${LAT_MIN},${LAT_MAX}] lon[${LON_MIN},${LON_MAX}] ==="
render_list -a \
  -z "$MIN_ZOOM" -Z "$MAX_ZOOM" \
  -g "$LAT_MIN" -G "$LAT_MAX" \
  -w "$LON_MIN" -W "$LON_MAX" \
  -n "$THREADS" \
  -s /run/renderd/renderd.sock \
  -t /data/tiles \
  -m default

echo "=== Seeding complete ==="
touch "$SHARE_DIR/seed-complete"

kill -TERM "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

echo "Done. Stop this add-on, then start osm-tile-server to serve the cached tiles."
