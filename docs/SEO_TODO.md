# SEO / Social Meta TODO (GitHub Pages)

Current status of `/docs/index.html`:
- Done: `title`, `description`, `viewport`, `favicon`, `apple-touch-icon`
- Missing: Open Graph, X Card, canonical URL, robots policy, structured data, crawler assets

## P0 (must do before promotion)

- [x] Add canonical URL
  - `<link rel="canonical" href="https://ymuichiro.github.io/koto-type/" />`
- [x] Add robots meta
  - `<meta name="robots" content="index,follow,max-image-preview:large" />`
- [x] Add Open Graph tags
  - `og:type=website`
  - `og:title`
  - `og:description`
  - `og:url`
  - `og:site_name`
  - `og:image` (absolute URL, recommended 1200x630)
- [x] Add X (Twitter) Card tags
  - `twitter:card=summary_large_image`
  - `twitter:title`
  - `twitter:description`
  - `twitter:image` (absolute URL)
  - `twitter:site` (optional, e.g. `@your_handle`)
- [x] Create social share image
  - File: `/docs/assets/og-image-1200x630.png`
  - Include app name + one value proposition + high contrast

## P1 (strongly recommended)

- [x] Add `meta name="theme-color"` for browser UI consistency
- [x] Add JSON-LD structured data (`SoftwareApplication`)
  - Fields: `name`, `applicationCategory`, `operatingSystem`, `offers`, `url`, `description`, `image`
- [x] Add `sitemap.xml`
  - For single-page site, include root URL + `lastmod`
- [x] Add `robots.txt`
  - Allow crawl and point to sitemap:
  - `Sitemap: https://<YOUR_PAGES_DOMAIN>/sitemap.xml`
- [x] Ensure all social/meta image URLs are absolute HTTPS URLs

## P2 (optional but useful)

- [ ] Add `og:locale` and alternates if multilingual pages are added
- [ ] Add `manifest.webmanifest` (if PWA-like install UX is desired)
- [ ] Add `twitter:creator` if you want author attribution

## Content SEO TODO

- [ ] Add one paragraph targeting broad English intent:
  - Example keywords: `voice to text mac`, `dictation app macOS`, `local speech recognition`
- [ ] Add FAQ section with real query phrasing
  - "Does KotoType send audio to the cloud?"
  - "How do I transcribe into any app on macOS?"
- [ ] Add internal links from repo docs to GitHub Pages URL
  - `README.md`, release notes, and project description

## Validation checklist

- [ ] Validate OG/X cards with:
  - X Card Validator
  - Facebook Sharing Debugger (OG compatibility check)
- [ ] Run Lighthouse (SEO + Best Practices) and target:
  - SEO >= 95
  - Best Practices >= 95
- [ ] Test link unfurl in:
  - X post preview
  - Slack/Discord preview
  - iMessage preview
