# Hosting Grid Landing Page on Cloudflare Pages

This repository includes a production-ready, zero-build static landing page located in the `public/` directory, optimized for Cloudflare Pages.

## 🚀 30-Second Setup Guide

1. **Log in to Cloudflare**:
   Navigate to the [Cloudflare Dashboard](https://dash.cloudflare.com/).

2. **Go to Workers & Pages**:
   In the left sidebar, click **Compute (Workers & Pages)** ➔ **Create application** ➔ **Pages** tab ➔ **Connect to Git**.

3. **Select Repository**:
   Choose `sushantdev-git/grid` (or your repository fork).

4. **Set Build Settings**:
   - **Project name**: `grid` (or your preferred subdomain)
   - **Production branch**: `main`
   - **Framework preset**: `None`
   - **Build command**: *(Leave completely blank)*
   - **Build output directory**: `public`

5. **Deploy**:
   Click **Save and Deploy**.

Cloudflare will deploy your site in ~2 seconds to `https://grid-xxx.pages.dev` with free automatic SSL, worldwide CDN edge caching, and security headers (configured via `public/_headers`).

---

## 🔒 Security & Performance Features
- **Zero Build Dependencies**: Pure HTML5, CSS3, and modern JavaScript—immune to `npm` audit vulnerabilities and build pipeline failures.
- **Pre-configured Headers**: `public/_headers` enforces strict Content-Type sniffing protection, X-Frame-Options, HSTS, and aggressive immutable caching for static assets.
- **Instant Clean Routing**: `public/_redirects` provides shortcuts for `/docs`, `/download`, and `/spec`.
