# Pure-Shell website

The site for [pure-shell.eu](https://pure-shell.eu): plain static HTML and CSS,
no build step, no JavaScript, no third-party requests (no CDN, fonts or
analytics). Dark by default, light on light systems.

| File | What |
|---|---|
| `index.html` | landing page |
| `privacy.html` | privacy policy |
| `terms/index.html` | terms of service |
| `style.css` | the one stylesheet |
| `web_assets/` | icon, favicon, touch icon, social preview (generated, see below); `ms-store-badge-*.svg`: Microsoft's official Store badge, unmodified |
| `robots.txt`, `sitemap.xml`, `404.html` | search and error pages |
| `CNAME` | a record of the custom domain (it is set in the repo's Pages settings) |

## Deploying

`.github/workflows/pages.yml` publishes this folder to GitHub Pages on every
push to `main` that touches it, or from the Actions tab. In the repo's
Settings > Pages, set the source to "GitHub Actions" and the custom domain to
`pure-shell.eu`, then enforce HTTPS once the certificate is issued.

DNS for the apex domain: four `A` records (`185.199.108.153`, `185.199.109.153`,
`185.199.110.153`, `185.199.111.153`), optionally four `AAAA` records
(`2606:50c0:8000::153` to `2606:50c0:8003::153`), and a `www` `CNAME` to
`janos-raul.github.io`. With Cloudflare, leave them "DNS only" until GitHub has
issued the certificate.

## Changing it

- The `web_assets/` images come from the app icon: run `tool/make-icons.py`.
- The Microsoft Store badges are Microsoft's own files from
  `https://get.microsoft.com/images/en-us%20dark.svg` (and `%20light.svg`),
  copied here unchanged so the site makes no third-party request. Don't edit them.
- `test/website_test.dart` checks the site: pages and links exist, nothing is
  loaded from another host, the footer links Privacy and Terms, and the privacy
  policy mentions every permission the app declares.
- The privacy policy and the terms describe what the app really does. Change
  them together with the app, and update the date at the top.
