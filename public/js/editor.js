// Slide editor: edits slide-decks/decks/*.json in place.
//
// Storage: FolderStore uses the File System Access API (Chromium) on the slide-decks folder, so
// the browser, the IDE, Claude Code, and git all see one file. FileStore covers other browsers
// (open one file, save downloads it) and the built-in sample.
// Rendering: SlidesEngine (engine-core.js) mirrors the Ruby templates; test/site_test.rb keeps
// them pixel-identical. Overflow: measureOverflows (measure.js), shared with `rake slides:lint`.
(function () {
  'use strict';

  const ENGINE = window.SLIDES_ENGINE_DATA;
  const E = window.SlidesEngine;
  const $ = (id) => document.getElementById(id);
  const isHash = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

  const MARKDOWN_FIELDS = ['content', 'left', 'right'];
  const LABELS = {
    title: 'Title', subtitle: 'Subtitle', heading: 'Heading', content: 'Body',
    left: 'Left column', right: 'Right column', image: 'Image (path in slide-decks, or URL)',
    image_prompt: 'Image prompt', notes: 'Speaker notes'
  };
  const NEW_SLIDE = {
    title: { title: 'Title', subtitle: 'One short line' },
    section: { heading: 'Section' },
    normal: { title: 'Title', body: '- First point\n- Second point' },
    two_column: { title: 'Title', left: '- Left', right: '- Right' },
    content_image: { title: 'Title', body: '- Point', image: '' },
    full_image: { image: '', title: 'Caption' }
  };
  const SAMPLE = {
    version: 2,
    deck: { title: 'Sample deck', output: { formats: ['png', 'pdf'] } },
    brand: 'civic-studio',
    slides: [
      { template: 'title', content: { title: 'Sample deck', subtitle: 'Edit me, then open your slide-decks folder' } },
      { template: 'normal', content: { title: 'Decks are data', body: '- One JSON file per deck\n- Templates and brands live in the engine\n- **Markdown** in body fields' } },
      { template: 'two_column', content: { title: 'Form and content', left: '**Content**\n- slide-decks/decks/*.json', right: '**Form**\n- slides/templates\n- slides/brands' } }
    ]
  };

  const state = {
    store: null,
    deckName: null,
    data: null,
    dirty: false,
    selected: 0,
    drawerTab: null,
    assetUrls: new Map()
  };

  // ---------- Storage ----------

  class FolderStore {
    constructor(dir) { this.dir = dir; this.label = dir.name; }

    async decksDir(create = false) {
      return this.dir.getDirectoryHandle('decks', { create });
    }

    async list() {
      const decks = await this.decksDir();
      const names = [];
      for await (const entry of decks.values()) {
        if (entry.kind === 'file' && entry.name.endsWith('.json') && !entry.name.includes('.resolved.')) {
          names.push(entry.name.replace(/\.json$/, ''));
        }
      }
      return names.sort();
    }

    async read(name) {
      const file = await (await (await this.decksDir()).getFileHandle(`${name}.json`)).getFile();
      return file.text();
    }

    async write(name, text, { create = false } = {}) {
      const handle = await (await this.decksDir(create)).getFileHandle(`${name}.json`, { create });
      const writable = await handle.createWritable();
      await writable.write(text);
      await writable.close();
    }

    async exists(name) {
      return (await this.list()).includes(name);
    }

    // Repo-relative asset path (assets/x/y.png) → object URL, or null when missing.
    async assetUrl(path) {
      try {
        const parts = path.split('/').filter(Boolean);
        let dir = this.dir;
        for (const part of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(part);
        const file = await (await dir.getFileHandle(parts[parts.length - 1])).getFile();
        return URL.createObjectURL(file);
      } catch (error) {
        return null;
      }
    }
  }

  class FileStore {
    constructor(name, text, label) { this.name = name; this.text = text; this.label = label; }
    async list() { return [this.name]; }
    async read() { return this.text; }
    async write(name, text) {
      this.text = text;
      const link = document.createElement('a');
      link.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
      link.download = `${name}.json`;
      link.click();
    }
    async exists(name) { return name === this.name; }
    async assetUrl() { return null; }
  }

  // ---------- Field access (keeps whatever key a deck already uses) ----------

  const templateOf = (raw) => raw.template || raw.type;
  const isLegacy = (raw) => !raw.template && !!raw.type;
  const specOf = (raw) => ENGINE.templates[templateOf(raw)];

  function locate(raw, field, create) {
    const aliases = ((specOf(raw) || {}).field_aliases || {})[field] || [field];
    if (field === 'content' && typeof raw.content === 'string') return { obj: raw, key: 'content' };
    if (isHash(raw.content)) {
      for (const alias of aliases) if (alias in raw.content) return { obj: raw.content, key: alias };
    }
    for (const alias of aliases) {
      if (alias === 'content' && isHash(raw.content)) continue;
      if (alias in raw) return { obj: raw, key: alias };
    }
    if (!create) return null;
    if (isLegacy(raw)) return { obj: raw, key: field };
    if (!isHash(raw.content)) raw.content = {};
    return { obj: raw.content, key: field === 'content' ? 'body' : field };
  }

  function getField(raw, field) {
    if (field === 'notes') return raw.notes || '';
    const loc = locate(raw, field, false);
    return loc ? (loc.obj[loc.key] ?? '') : '';
  }

  function setField(raw, field, value) {
    if (field === 'notes') {
      if (value === '') delete raw.notes; else raw.notes = value;
      return;
    }
    const loc = locate(raw, field, value !== '');
    if (!loc) return;
    if (value === '') delete loc.obj[loc.key]; else loc.obj[loc.key] = value;
  }

  const slidesOf = (data) => (Array.isArray(data) ? data : data.slides);
  const fieldsOf = (raw) => {
    const spec = specOf(raw) || {};
    return [...(spec.required_fields || []), ...(spec.optional_fields || [])];
  };

  // ---------- Rendering ----------

  function normalized() {
    try {
      return { deck: E.normalizeDeck(state.data, ENGINE), error: null };
    } catch (error) {
      return { deck: null, error };
    }
  }

  const isRelativeAsset = (src) => src && !/^(https?:|data:|blob:|\/)/.test(src);

  async function resolveAsset(src) {
    if (!isRelativeAsset(src) || !state.store) return src;
    if (!state.assetUrls.has(src)) state.assetUrls.set(src, await state.store.assetUrl(src));
    return state.assetUrls.get(src);
  }

  let renderToken = 0;
  async function renderPreview() {
    const token = ++renderToken;
    const warnings = $('warnings');
    const { deck, error } = normalized();
    warnings.replaceChildren();
    if (error) {
      addWarning(error.message, true);
      return;
    }
    const entry = deck.slides[state.selected];
    if (!entry) return;
    const slide = Object.assign({}, entry.slide);
    if (slide.image) {
      const url = await resolveAsset(slide.image);
      if (url) slide.image = url;
      else addWarning(`Image not found in the decks folder: ${slide.image}`, true);
    }
    if (token !== renderToken) return;
    entry.missing.forEach((field) => addWarning(`Missing required field: ${LABELS[field] || field}`, true));

    const frame = $('preview');
    frame.onload = () => {
      if (token !== renderToken) return;
      const measure = () => {
        const overflows = measureOverflows(frame.contentDocument);
        document.querySelectorAll('#warnings li.overflow').forEach((li) => li.remove());
        overflows.forEach((o) => {
          const edges = [o.bottom ? `${o.bottom}px past bottom` : '', o.right ? `${o.right}px past right` : ''].filter(Boolean).join(', ');
          addWarning(`Overflow: "${o.text}" ${edges}. Split the slide or pick a denser template.`, false, 'overflow');
        });
        const item = document.querySelector(`#slide-list li[data-index="${state.selected}"] .flag`);
        if (item) item.textContent = overflows.length || entry.missing.length ? ' ⚠' : '';
      };
      measure();
      // Web fonts can reflow text after load; measure again once they settle.
      frame.contentDocument.fonts.ready.then(() => { if (token === renderToken) measure(); });
    };
    frame.srcdoc = E.renderSlide(slide, state.selected + 1, deck.config, ENGINE);
  }

  function addWarning(text, isError, kind) {
    const li = document.createElement('li');
    li.textContent = text;
    if (isError) li.classList.add('error');
    if (kind) li.classList.add(kind);
    $('warnings').append(li);
  }

  function fitPreview() {
    const box = $('preview-frame');
    $('preview').style.transform = `scale(${box.clientWidth / 1920})`;
  }

  // ---------- Slide list ----------

  function slideLabel(entry, raw) {
    if (!entry) return templateOf(raw) || '(invalid)';
    const s = entry.slide;
    return String(s.title || s.heading || s.image || '(untitled)').replace(/<[^>]+>/g, '');
  }

  function renderList() {
    const { deck } = normalized();
    const list = $('slide-list');
    list.replaceChildren();
    slidesOf(state.data).forEach((raw, index) => {
      const entry = deck && deck.slides[index];
      const li = document.createElement('li');
      li.dataset.index = index;
      if (index === state.selected) li.classList.add('selected');
      li.innerHTML = `<span class="num">${index + 1}</span>
<span class="title"></span>
<span class="meta">${E.escapeHtml(templateOf(raw) || '?')}<span class="flag">${entry && entry.missing.length ? ' ⚠' : ''}</span></span>
<span class="actions">
<button type="button" data-action="up" title="Move up">↑</button>
<button type="button" data-action="down" title="Move down">↓</button>
<button type="button" data-action="duplicate" title="Duplicate">Duplicate</button>
<button type="button" data-action="delete" title="Delete">Delete</button>
</span>`;
      li.querySelector('.title').textContent = slideLabel(entry, raw);
      list.append(li);
    });
  }

  function select(index) {
    const count = slidesOf(state.data).length;
    state.selected = Math.max(0, Math.min(index, count - 1));
    renderList();
    renderInspector();
    renderDrawer();
    renderPreview();
  }

  // ---------- Inspector ----------

  function renderInspector() {
    const raw = slidesOf(state.data)[state.selected];
    $('inspector').hidden = !raw;
    if (!raw) return;
    const spec = specOf(raw) || {};
    $('template-select').value = templateOf(raw);
    $('template-help').textContent = [spec.description, ...(spec.constraints || [])].filter(Boolean).join(' ');

    const fields = $('fields');
    fields.replaceChildren();
    [...fieldsOf(raw), 'notes'].forEach((field) => {
      const label = document.createElement('label');
      const required = (spec.required_fields || []).includes(field);
      label.innerHTML = `<span>${E.escapeHtml(LABELS[field] || field)}${required ? ' <span class="req">*</span>' : ''}</span>`;
      const multiline = MARKDOWN_FIELDS.includes(field) || field === 'notes' || field === 'image_prompt';
      const input = document.createElement(multiline ? 'textarea' : 'input');
      if (!multiline) input.type = 'text';
      input.dataset.field = field;
      input.value = getField(raw, field);
      input.addEventListener('input', () => {
        setField(raw, field, input.value);
        changed({ list: field === 'title' || field === 'heading' || field === 'image' });
      });
      label.append(input);
      if (MARKDOWN_FIELDS.includes(field)) {
        const open = document.createElement('button');
        open.type = 'button';
        open.className = 'open-drawer';
        open.textContent = 'Edit in drawer';
        open.addEventListener('click', () => openDrawer(field));
        label.append(open);
      }
      fields.append(label);
    });
  }

  function syncInspectorValues() {
    const raw = slidesOf(state.data)[state.selected];
    if (!raw) return;
    document.querySelectorAll('#fields [data-field]').forEach((input) => {
      if (input !== document.activeElement) input.value = getField(raw, input.dataset.field);
    });
  }

  // ---------- Markdown drawer ----------

  function drawerTabs() {
    const raw = slidesOf(state.data)[state.selected];
    const tabs = raw ? fieldsOf(raw).filter((f) => MARKDOWN_FIELDS.includes(f)) : [];
    return [...tabs, 'notes', 'deck'];
  }

  function openDrawer(tab) {
    $('drawer').hidden = false;
    document.body.classList.add('drawer-open');
    if (tab) state.drawerTab = tab;
    renderDrawer();
    $('drawer-text').focus();
  }

  function closeDrawer() {
    $('drawer').hidden = true;
    document.body.classList.remove('drawer-open');
  }

  function renderDrawer() {
    if ($('drawer').hidden || !state.data) return;
    const tabs = drawerTabs();
    if (!tabs.includes(state.drawerTab)) state.drawerTab = tabs[0];
    const bar = $('drawer-tabs');
    bar.replaceChildren();
    tabs.forEach((tab) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.role = 'tab';
      button.dataset.tab = tab;
      button.textContent = tab === 'deck' ? 'Deck JSON' : (LABELS[tab] || tab);
      button.setAttribute('aria-selected', String(tab === state.drawerTab));
      button.addEventListener('click', () => { state.drawerTab = tab; renderDrawer(); $('drawer-text').focus(); });
      bar.append(button);
    });
    const text = $('drawer-text');
    if (text !== document.activeElement || text.dataset.tab !== state.drawerTab || text.dataset.slide !== String(state.selected)) {
      text.value = drawerValue();
    }
    text.dataset.tab = state.drawerTab;
    text.dataset.slide = String(state.selected);
    $('drawer-error').textContent = '';
  }

  function drawerValue() {
    if (state.drawerTab === 'deck') return JSON.stringify(state.data, null, 2);
    const raw = slidesOf(state.data)[state.selected];
    return raw ? String(getField(raw, state.drawerTab)) : '';
  }

  function onDrawerInput() {
    const value = $('drawer-text').value;
    if (state.drawerTab === 'deck') {
      try {
        const parsed = JSON.parse(value);
        E.normalizeDeck(parsed, ENGINE);
        state.data = parsed;
        $('drawer-error').textContent = '';
        state.selected = Math.min(state.selected, slidesOf(parsed).length - 1);
        changed({ list: true, inspector: true });
      } catch (error) {
        $('drawer-error').textContent = error.message;
      }
      return;
    }
    const raw = slidesOf(state.data)[state.selected];
    if (!raw) return;
    setField(raw, state.drawerTab, value);
    changed({});
  }

  // ---------- Changes and saving ----------

  let previewTimer = null;
  function changed({ list = false, inspector = false } = {}) {
    setDirty(true);
    if (list) renderList();
    if (inspector) renderInspector(); else syncInspectorValues();
    if (state.drawerTab === 'deck' && $('drawer-text') !== document.activeElement) renderDrawer();
    clearTimeout(previewTimer);
    previewTimer = setTimeout(renderPreview, 120);
  }

  function setDirty(dirty) {
    state.dirty = dirty;
    const status = $('status');
    status.textContent = dirty ? 'Unsaved changes' : status.textContent;
    status.classList.toggle('dirty', dirty);
  }

  async function save() {
    if (!state.data || !state.store) return;
    const { error } = normalized();
    if (error) {
      $('status').textContent = `Not saved: ${error.message}`;
      return;
    }
    await state.store.write(state.deckName, JSON.stringify(state.data, null, 2) + '\n');
    setDirty(false);
    $('status').textContent = `Saved decks/${state.deckName}.json at ${new Date().toLocaleTimeString()}`;
    document.body.dataset.saved = String(Number(document.body.dataset.saved || 0) + 1);
  }

  async function loadDeck(name) {
    if (state.dirty && !confirm('Discard unsaved changes?')) {
      $('deck-select').value = state.deckName;
      return;
    }
    const text = await state.store.read(name);
    state.deckName = name;
    state.data = JSON.parse(text);
    state.selected = 0;
    state.assetUrls = new Map();
    setDirty(false);
    $('status').textContent = `${state.store.label} / decks/${name}.json`;
    $('deck-select').value = name;
    renderBrandSelect();
    enableEditing();
    select(0);
  }

  function enableEditing() {
    $('welcome').hidden = true;
    $('preview-frame').hidden = false;
    ['save', 'add-slide', 'add-template', 'brand-select', 'drawer-toggle', 'deck-select'].forEach((id) => { $(id).disabled = false; });
    $('brand-select').disabled = Array.isArray(state.data);
    $('new-deck').disabled = !(state.store instanceof FolderStore);
    requestAnimationFrame(fitPreview);
  }

  async function useStore(store) {
    state.store = store;
    const names = await store.list();
    const select = $('deck-select');
    select.replaceChildren(...names.map((name) => new Option(name, name)));
    if (names.length) await loadDeck(names[0]);
    else $('status').textContent = `${store.label}: no decks/*.json yet`;
    $('new-deck').disabled = !(store instanceof FolderStore);
  }

  function renderBrandSelect() {
    const select = $('brand-select');
    const current = Array.isArray(state.data) ? '' : (state.data.brand || (state.data.deck && state.data.deck.brand) || '');
    select.replaceChildren(new Option('(none)', ''), ...Object.entries(ENGINE.brands).map(([key, brand]) => new Option(brand.name, key)));
    select.value = current;
  }

  // ---------- Wiring ----------

  function bind() {
    $('template-select').replaceChildren(...Object.entries(ENGINE.templates).map(([key, spec]) => new Option(spec.label || key, key)));
    $('add-template').replaceChildren(...Object.entries(ENGINE.templates).map(([key, spec]) => new Option(spec.label || key, key)));
    $('add-template').value = 'normal';

    if (!window.showDirectoryPicker) {
      $('open-folder').hidden = true;
      $('open-file-label').hidden = false;
      $('no-fs-note').hidden = false;
    }

    $('open-folder').addEventListener('click', async () => {
      try {
        const dir = await window.showDirectoryPicker({ id: 'slide-decks', mode: 'readwrite' });
        await dir.getDirectoryHandle('decks', { create: false }).catch(() => {
          throw new Error(`"${dir.name}" has no decks/ folder. Pick your slide-decks folder.`);
        });
        await useStore(new FolderStore(dir));
      } catch (error) {
        if (error.name !== 'AbortError') $('status').textContent = error.message;
      }
    });

    $('open-file').addEventListener('change', async (event) => {
      const file = event.target.files[0];
      if (!file) return;
      await useStore(new FileStore(file.name.replace(/\.json$/, ''), await file.text(), 'file'));
    });

    $('try-sample').addEventListener('click', () => useStore(new FileStore('sample', JSON.stringify(SAMPLE, null, 2) + '\n', 'sample')));
    $('deck-select').addEventListener('change', (event) => loadDeck(event.target.value));
    $('save').addEventListener('click', save);

    $('new-deck').addEventListener('click', async () => {
      const name = (prompt('New deck name (letters, numbers, - and _):') || '').trim();
      if (!name) return;
      if (!/^[a-z0-9_-]+$/i.test(name)) { $('status').textContent = 'Use letters, numbers, - and _ only.'; return; }
      if (await state.store.exists(name)) { $('status').textContent = `decks/${name}.json already exists.`; return; }
      const deck = {
        version: 2,
        deck: { title: name, output: { formats: ['png', 'pdf'] } },
        brand: 'civic-studio',
        slides: [{ template: 'title', content: { title: name } }]
      };
      await state.store.write(name, JSON.stringify(deck, null, 2) + '\n', { create: true });
      state.dirty = false;
      await useStore(state.store);
      await loadDeck(name);
    });

    $('brand-select').addEventListener('change', (event) => {
      const value = event.target.value;
      const target = isHash(state.data.deck) && 'brand' in state.data.deck ? state.data.deck : state.data;
      if (value) target.brand = value; else delete target.brand;
      changed({ list: false });
    });

    $('template-select').addEventListener('change', (event) => {
      const raw = slidesOf(state.data)[state.selected];
      if (isLegacy(raw)) raw.type = event.target.value; else raw.template = event.target.value;
      changed({ list: true, inspector: true });
      renderDrawer();
    });

    $('add-slide').addEventListener('click', () => {
      const template = $('add-template').value;
      const slides = slidesOf(state.data);
      slides.splice(state.selected + 1, 0, { template, content: Object.assign({}, NEW_SLIDE[template]) });
      setDirty(true);
      select(state.selected + 1);
    });

    $('slide-list').addEventListener('click', (event) => {
      const li = event.target.closest('li');
      if (!li) return;
      const index = Number(li.dataset.index);
      const action = event.target.dataset.action;
      const slides = slidesOf(state.data);
      if (!action) return select(index);
      if (action === 'up' && index > 0) { slides.splice(index - 1, 0, slides.splice(index, 1)[0]); setDirty(true); return select(index - 1); }
      if (action === 'down' && index < slides.length - 1) { slides.splice(index + 1, 0, slides.splice(index, 1)[0]); setDirty(true); return select(index + 1); }
      if (action === 'duplicate') { slides.splice(index + 1, 0, JSON.parse(JSON.stringify(slides[index]))); setDirty(true); return select(index + 1); }
      if (action === 'delete' && slides.length > 1 && confirm(`Delete slide ${index + 1}?`)) { slides.splice(index, 1); setDirty(true); return select(index); }
    });

    $('drawer-toggle').addEventListener('click', () => openDrawer());
    $('drawer-close').addEventListener('click', closeDrawer);
    $('drawer-text').addEventListener('input', onDrawerInput);

    // Drawer height: drag the handle; remembered per browser.
    try {
      const saved = localStorage.getItem('slides.drawerHeight');
      if (saved) document.documentElement.style.setProperty('--drawer-height', saved);
    } catch (error) { /* storage unavailable: default height */ }
    $('drawer-handle').addEventListener('pointerdown', (down) => {
      const startY = down.clientY;
      const startHeight = $('drawer').offsetHeight;
      const move = (event) => {
        const height = `${Math.max(120, Math.min(window.innerHeight * 0.8, startHeight + startY - event.clientY))}px`;
        document.documentElement.style.setProperty('--drawer-height', height);
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        try { localStorage.setItem('slides.drawerHeight', getComputedStyle(document.documentElement).getPropertyValue('--drawer-height').trim()); } catch (error) { /* ignore */ }
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up, { once: true });
    });

    document.addEventListener('keydown', (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key === 's') { event.preventDefault(); save(); }
      if (event.ctrlKey && event.key === '`') { event.preventDefault(); if ($('drawer').hidden) openDrawer(); else closeDrawer(); }
    });

    window.addEventListener('beforeunload', (event) => { if (state.dirty) { event.preventDefault(); event.returnValue = ''; } });
    new ResizeObserver(fitPreview).observe($('preview-frame'));
  }

  bind();
  window.SlideEditor = { state, save, select, openDrawer };
})();
