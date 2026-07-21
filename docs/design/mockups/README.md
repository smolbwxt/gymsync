# Redesign proof sources (2026-07-20 visual-language redesign)

These HTML templates are the **authoritative design direction** for the
near-black Onyx redesign (spec:
`docs/superpowers/specs/2026-07-20-visual-language-redesign-design.md`).
Interactive builds were published as Claude artifacts during the design
sessions; the templates here are the committed sources (Archivo font data
stripped to `__ARCHIVO_*__` placeholders — inject from
`GymSyncApp/GymSync/DesignSystem/Fonts/` to re-render).

- `home-redesign.template.html` — Home direction study (accent picker, group
  calendar, streak ring)
- `redesign-proofs.template.html` — all five tabs (Home, Library, Social,
  Stats, You) + global accent switching
- `deep-proofs.template.html` — live session, solo workout, exercise detail,
  campaign detail

## Parity-harness status

The old design-parity baseline (`../Gym Sync App Designs.dc.html` frames +
`../frame-map.json`, Ink palette) is **superseded** by this redesign for every
redesigned screen. The CI `parity` job is *report-only* (it never fails a
build) and still diffs against the Ink frames, so its report shows expected
wholesale divergence until the frame set is re-rendered in the Onyx language.
Catalog/screenshot captures now pin **Onyx + sky** (GymSyncApp.swift's
UITEST_CATALOG branch), so `app-*.png` captures show the real redesign.

Re-basing the frame set (rendering per-screen Onyx frames from these templates
and re-pointing `frame-map.json`) is tracked as follow-up work; per-screen
`accepted-deviations.json` entries tied to Ink frames should be re-adjudicated
then, not piecemeal.
