# Third-party assets

## `assets/whale.glb`

- **Model**: "Whale"
- **Author**: Quaternius
- **Source**: [Poly Pizza](https://poly.pizza/m/JGFwp6xWgk) — `https://static.poly.pizza/7300e697-2543-4a9a-a77d-dedf29251fd7.glb`
- **Licence**: CC0 1.0 Universal (Public Domain), per the listing —
  https://creativecommons.org/publicdomain/zero/1.0/

Verified by fetching the model page directly (`poly.pizza/m/JGFwp6xWgk`) and confirming its
page title ("Whale - Free 3D Model By Quaternius"), its `og:image` meta tag, and the CDN glb
URL it links to all resolve to the exact UUID (`7300e697-2543-4a9a-a77d-dedf29251fd7`) already
vendored in this repo, and that its licence badge links to the CC0 deed above. No modification
was made to the geometry beyond what `render_vessel.py` does at load time (weld duplicate
vertices, reorient/scale to `BODY_LENGTH`, recentre on the origin) — see `load_shell()`.
