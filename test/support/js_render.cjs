// Test helper: render decks with the browser engine (public/js/engine-core.js) in Node.
// stdin: [{ name, data }]  stdout: { name: [html, ...] }
const fs = require('fs');
const engine = require('../../public/js/engine-core.js');
const data = require('../../public/js/engine-data.js');

const decks = JSON.parse(fs.readFileSync(0, 'utf8'));
const out = {};
for (const { name, data: deck } of decks) {
  const { config, slides } = engine.normalizeDeck(deck, data);
  out[name] = slides.map(({ slide }, i) => engine.renderSlide(slide, i + 1, config, data));
}
process.stdout.write(JSON.stringify(out));
