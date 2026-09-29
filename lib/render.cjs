// Batch renderer: one Chrome for a whole deck.
//
// stdin:  { root, timeout, jobs: [{ id, html_path, out, format: "png"|"pdf"|"none",
//           width, height, full_page, measure }] }
// stdout: one JSON line per job: { id, ok, out, bytes, overflows, error }
//
// Pages load at http://slides.local/__page so relative asset paths resolve against `root`
// (e.g. public/images/x.png -> <root>/public/images/x.png). Absolute paths are served as-is.
// Any failed request (missing file, dead remote image) fails the job; nothing renders broken silently.

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const ORIGIN = 'http://slides.local';
const PAGE_URL = `${ORIGIN}/__page`;
const MIME = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.svg': 'image/svg+xml', '.webp': 'image/webp', '.css': 'text/css', '.js': 'text/javascript',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf'
};

function localFile(root, url) {
  const rel = decodeURIComponent(new URL(url).pathname);
  const candidates = [path.join(root, rel), rel];
  return candidates.find((p) => fs.existsSync(p) && fs.statSync(p).isFile());
}

const { measureOverflows } = require('../public/js/measure.js');

async function runJob(browser, root, timeout, job) {
  const page = await browser.newPage();
  const failures = [];
  try {
    await page.setViewport({ width: job.width, height: job.height });
    await page.setRequestInterception(true);
    page.on('request', (request) => {
      const url = request.url();
      if (url === PAGE_URL) {
        return request.respond({ contentType: 'text/html', body: fs.readFileSync(job.html_path, 'utf8') });
      }
      if (url === `${ORIGIN}/favicon.ico`) return request.respond({ status: 204, body: '' });
      if (url.startsWith(ORIGIN)) {
        const file = localFile(root, url);
        if (!file) {
          failures.push(`missing file: ${decodeURIComponent(new URL(url).pathname).replace(/^\//, '')}`);
          return request.respond({ status: 404, body: '' });
        }
        return request.respond({
          contentType: MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
          body: fs.readFileSync(file)
        });
      }
      request.continue();
    });
    page.on('requestfailed', (request) => failures.push(`request failed: ${request.url().slice(0, 120)} (${request.failure()?.errorText})`));
    page.on('response', (response) => {
      if (response.status() >= 400 && !response.url().startsWith(ORIGIN)) {
        failures.push(`HTTP ${response.status()}: ${response.url().slice(0, 120)}`);
      }
    });

    await page.goto(PAGE_URL, { waitUntil: 'networkidle0', timeout });
    await page.evaluate(() => document.fonts.ready);

    if (failures.length) throw new Error(failures.join('; '));

    const result = { id: job.id, ok: true, out: job.out, overflows: [] };
    if (job.measure) result.overflows = await page.evaluate(measureOverflows);  // shared with the editor

    if (job.format === 'png') {
      await page.screenshot({ path: job.out, type: 'png', fullPage: !!job.full_page });
    } else if (job.format === 'pdf') {
      await page.pdf({ path: job.out, printBackground: true, preferCSSPageSize: true, timeout });
    }
    if (job.format !== 'none') result.bytes = fs.statSync(job.out).size;
    return result;
  } finally {
    await page.close().catch(() => {});
  }
}

async function main() {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  const timeout = input.timeout || 60000;
  const browser = await puppeteer.launch({ protocolTimeout: timeout * 2 });
  let failed = 0;
  try {
    for (const job of input.jobs) {
      let result;
      for (let attempt = 1; attempt <= 2; attempt++) {
        try {
          result = await runJob(browser, input.root, timeout, job);
          break;
        } catch (error) {
          result = { id: job.id, ok: false, out: job.out, error: String(error.message || error) };
          // Missing assets won't appear on retry; only retry Chrome/timeouts.
          if (/missing file|HTTP \d|request failed/.test(result.error)) break;
        }
      }
      if (!result.ok) failed++;
      process.stdout.write(JSON.stringify(result) + '\n');
    }
  } finally {
    await browser.close();
  }
  process.exit(failed ? 1 : 0);
}

main().catch((error) => {
  process.stderr.write(String(error.stack || error) + '\n');
  process.exit(2);
});
