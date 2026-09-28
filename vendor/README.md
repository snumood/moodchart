# Reviewed browser dependencies

`manifest.json` records the exact served versions, source URLs and SHA-256
hashes of these browser scripts. Original license comments are retained.
Serving them locally prevents an unreviewed CDN version change while a user
has a persistent login token or a record open.

Before updating, run a dependency audit and verify login, Chart.js time axes,
the Luxon adapter and annotations. Keep CSP restricted to local scripts.

The Gaegu handwriting font (SIL Open Font License 1.1) is served from
`vendor/fonts/` because the CSP allows fonts from this site only. Only the
unicode-range subsets a page actually uses are downloaded by the browser.
