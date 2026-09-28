# Reviewed browser dependencies

`manifest.json` records the exact served versions, source URLs and SHA-256
hashes of these browser scripts. Original license comments are retained.
Serving them locally prevents an unreviewed CDN version change while a user
has a persistent login token or a record open.

Before updating, run a dependency audit and verify login, Chart.js time axes,
the Luxon adapter and annotations. Keep CSP restricted to local scripts.

Fonts (SIL Open Font License 1.1) are served from `vendor/fonts/` because the
CSP allows fonts from this site only: Pretendard (text), MaruBuri (Korean
headings, subset to the glyphs the app uses; re-run the subset if new Korean
heading text is added), Nanum Pen Script (handwritten entries) and Cormorant
Garamond (printed numerals). Browsers download only the unicode-range subsets
a page actually uses.
