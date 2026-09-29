// Drives public/index.html in Chrome against a real folder on disk.
// window.showDirectoryPicker is replaced by a handle whose reads and writes go through
// exposed Node functions to argv[2], so the page's own File System Access code path runs.
// stdout: JSON report consumed by test/editor_test.rb.
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const root = process.argv[2];
const pageUrl = 'file://' + path.resolve(__dirname, '../../public/index.html');

const fakeFs = () => {
  const file = (rel, name) => ({
    kind: 'file',
    name,
    async queryPermission() { return 'granted'; },
    async requestPermission() { return 'granted'; },
    async getFile() {
      const b64 = await window.__fsRead(rel);
      if (b64 === null) throw new DOMException('not found', 'NotFoundError');
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      return new File([bytes], name);
    },
    async createWritable() {
      let text = '';
      return { async write(data) { text += data; }, async close() { await window.__fsWrite(rel, text); } };
    }
  });
  const dir = (rel, name) => ({
    kind: 'directory',
    name,
    async getDirectoryHandle(child, opts = {}) {
      const childRel = rel ? `${rel}/${child}` : child;
      if (!(await window.__fsIsDir(childRel)) && !opts.create) throw new DOMException('not found', 'NotFoundError');
      return dir(childRel, child);
    },
    async getFileHandle(child, opts = {}) {
      const childRel = rel ? `${rel}/${child}` : child;
      if ((await window.__fsRead(childRel)) === null && !opts.create) throw new DOMException('not found', 'NotFoundError');
      return file(childRel, child);
    },
    async *values() {
      for (const [name, kind] of await window.__fsList(rel)) yield kind === 'file' ? file(`${rel}/${name}`, name) : dir(`${rel}/${name}`, name);
    }
  });
  window.showDirectoryPicker = async () => (window.__pickDecksDir ? dir('decks', 'decks') : dir('', 'slide-decks'));
  window.showOpenFilePicker = async () => [file('decks/fixture.json', 'fixture.json')];
};

(async () => {
  const browser = await puppeteer.launch();
  const report = { errors: [] };
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1600, height: 1000 });
    page.on('pageerror', (e) => report.errors.push(String(e)));
    page.on('dialog', (d) => d.accept());
    const abs = (rel) => path.join(root, rel);
    await page.exposeFunction('__fsRead', (rel) => (fs.existsSync(abs(rel)) && fs.statSync(abs(rel)).isFile() ? fs.readFileSync(abs(rel)).toString('base64') : null));
    await page.exposeFunction('__fsWrite', (rel, text) => { fs.mkdirSync(path.dirname(abs(rel)), { recursive: true }); fs.writeFileSync(abs(rel), text); return true; });
    await page.exposeFunction('__fsIsDir', (rel) => fs.existsSync(abs(rel)) && fs.statSync(abs(rel)).isDirectory());
    await page.exposeFunction('__fsList', (rel) => fs.readdirSync(abs(rel), { withFileTypes: true }).map((e) => [e.name, e.isDirectory() ? 'directory' : 'file']));
    await page.evaluateOnNewDocument(fakeFs);
    await page.goto(pageUrl);

    const deckPath = abs('decks/fixture.json');
    const original = fs.readFileSync(deckPath, 'utf8');
    const saves = async (n) => page.waitForFunction((k) => Number(document.body.dataset.saved || 0) >= k, { timeout: 10000 }, n);

    const visible = (sel) => page.$eval(sel, (el) => el.getClientRects().length > 0);
    report.drawerHiddenAtStart = !(await visible('#drawer'));

    await page.click('#open-folder');
    await page.waitForFunction(() => document.querySelectorAll('#slide-list li').length > 0);
    report.decks = await page.$$eval('#deck-select option', (os) => os.map((o) => o.value));
    report.slideCount = await page.$$eval('#slide-list li', (ls) => ls.length);

    // 1. Open and save without edits: the file must come back byte-identical.
    await page.click('#save');
    await saves(1);
    report.roundTripIdentical = fs.readFileSync(deckPath, 'utf8') === original;

    // 2. Edit slide 2's body in the Markdown drawer; the preview updates live; save writes it.
    await page.click('#slide-list li[data-index="1"]');
    await page.click('#drawer-toggle');
    await page.$eval('#drawer-text', (t) => { t.value = '- Edited in the drawer\n- **Second** point'; t.dispatchEvent(new Event('input')); });
    await page.waitForFunction(() => {
      const doc = document.getElementById('preview').contentDocument;
      return doc && doc.body && doc.body.textContent.includes('Edited in the drawer');
    }, { timeout: 10000 });
    report.previewUpdated = true;
    report.drawerTabs = await page.$$eval('#drawer-tabs button', (bs) => bs.map((b) => b.textContent));
    report.drawerVisibleWhenOpen = await visible('#drawer');
    await page.click('#drawer-close');
    report.drawerHiddenAfterClose = !(await visible('#drawer'));
    await page.click('#drawer-toggle');
    await page.keyboard.down('Control'); await page.keyboard.press('s'); await page.keyboard.up('Control');
    await saves(2);
    report.afterEdit = JSON.parse(fs.readFileSync(deckPath, 'utf8'));

    // 3. Overflow shows as a warning.
    await page.$eval('#drawer-text', (t) => { t.value = Array.from({ length: 20 }, (_, i) => `- Bullet ${i + 1} is long enough to push past the bottom`).join('\n'); t.dispatchEvent(new Event('input')); });
    await page.waitForSelector('#warnings li.overflow', { timeout: 10000 });
    report.overflowWarning = await page.$eval('#warnings li.overflow', (li) => li.textContent);

    // 4. Structure: add a section slide, move it up, delete slide 1; save.
    await page.$eval('#drawer-text', (t) => { t.value = '- Short again'; t.dispatchEvent(new Event('input')); });
    await page.select('#add-template', 'section');
    await page.click('#add-slide');
    await page.click('#slide-list li.selected [data-action="up"]');
    await page.click('#slide-list li[data-index="0"]');
    await page.click('#slide-list li.selected [data-action="delete"]');
    await page.click('#save');
    await saves(3);
    report.afterStructure = JSON.parse(fs.readFileSync(deckPath, 'utf8'));

    // 5. Asset images load from the folder.
    await page.select('#add-template', 'content_image');
    await page.click('#add-slide');
    await page.$eval('#fields input[data-field="image"]', (i) => { i.value = 'assets/fixture/dot.png'; i.dispatchEvent(new Event('input')); });
    await page.waitForFunction(() => {
      const img = document.getElementById('preview').contentDocument?.querySelector('.column.image img');
      return img && img.src.startsWith('blob:') && img.complete && img.naturalWidth > 0;
    }, { timeout: 10000 });
    report.assetLoaded = true;
    await page.click('#save');
    await saves(4);

    // 6. Open deck: one .json file, edited and saved in place.
    await page.goto(pageUrl);
    await page.click('#open-deck');
    await page.waitForFunction(() => document.querySelectorAll('#slide-list li').length > 0);
    report.openDeckStatus = await page.$eval('#status', (s) => s.textContent);
    report.openDeckNewDeckDisabled = await page.$eval('#new-deck', (b) => b.disabled);
    await page.$eval('#fields input[data-field="heading"], #fields input[data-field="title"]', (i) => { i.value = 'Saved through Open deck'; i.dispatchEvent(new Event('input')); });
    await page.click('#save');
    await saves(1);
    report.afterOpenDeck = JSON.parse(fs.readFileSync(deckPath, 'utf8'));

    // 7. Open folder on decks/ itself: decks list, but images need the repo root.
    await page.goto(pageUrl);
    await page.evaluate(() => { window.__pickDecksDir = true; });
    await page.click('#open-folder');
    await page.waitForFunction(() => document.querySelectorAll('#slide-list li').length > 0);
    report.decksDirDecks = await page.$$eval('#deck-select option', (os) => os.map((o) => o.value));
    const imageIndex = report.afterOpenDeck.slides.findIndex((s) => s.template === 'content_image');
    await page.click(`#slide-list li[data-index="${imageIndex}"]`);
    await page.waitForSelector('#warnings li', { timeout: 10000 });
    report.decksDirImageWarning = await page.$eval('#warnings', (w) => w.textContent);
  } catch (error) {
    report.errors.push(String(error.stack || error));
  } finally {
    await browser.close();
  }
  process.stdout.write(JSON.stringify(report));
})();
