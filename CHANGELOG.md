# Changelog

## 1.0.2

- Fix: the packaged `render_list` in this image only supports numeric tile bounds (`-x/-X/-y/-Y`), not the lat/lon flags (`-g/-G/-w/-W`) documented upstream for newer mod_tile releases. Passing them was silently ignored after an "invalid option" warning, leaving `-a` with no bounds at all -- i.e. seeding the entire planet's tile grid. Now computes tile x/y bounds per zoom level with the standard slippy-map formula and calls `render_list` once per zoom.

## 1.0.1

- Fix: `chown` the `/share/osm-tiles` directories to the `renderer` user after creating them. Without it, `renderd` (which runs as `renderer`, not root) got `Permission denied` writing every metatile, since `mkdir` left them root-owned.

## 1.0.0

- Initial release: wraps `overv/openstreetmap-tile-server:2.3.0` to import an OSM extract and seed a tile cache under `/share/osm-tiles` for `osm-tile-server` to serve.
