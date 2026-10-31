# Wraps the upstream prebuilt image (https://github.com/Overv/openstreetmap-tile-server),
# which already bundles PostgreSQL+PostGIS, osm2pgsql, renderd/mod_tile and the
# openstreetmap-carto stylesheet. Bump this tag together with "version" in config.json
# to update.
FROM overv/openstreetmap-tile-server:2.3.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends jq \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY run.sh /addon-run.sh
RUN chmod +x /addon-run.sh

ENTRYPOINT ["/addon-run.sh"]
