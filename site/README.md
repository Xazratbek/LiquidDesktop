# Liquid Desktop Web Platform

This directory contains the public-facing Liquid Desktop website. It is a
dependency-free static site designed for Cloudflare Workers static assets.

Live deployment: [liquid-desktop-xazratbek.pages.dev](https://liquid-desktop-xazratbek.pages.dev/)

## Local preview

From the repository root:

```bash
python3 -m http.server 8080 --directory site
```

Open <http://localhost:8080> in a browser.

## Cloudflare Workers deployment

The repository root contains `wrangler.jsonc`, which points Wrangler at this
directory. From the repository root:

```bash
npx wrangler login
npx wrangler deploy
```

No frontend build step is required. HTML, CSS, JavaScript, images, posters,
and MP4 previews are uploaded as static assets.

## Motion and interaction

- The hero and controller sections use looping product videos.
- `IntersectionObserver` powers section reveals, active story beats, and lazy
  video loading.
- The theme gallery uses horizontal scroll snapping with smooth arrow controls.
- The battery tile animates when it enters the viewport.
- `prefers-reduced-motion` disables non-essential movement for accessibility.

## Main pages

- [`index.html`](index.html): product landing page
- [`privacy.html`](privacy.html): privacy policy