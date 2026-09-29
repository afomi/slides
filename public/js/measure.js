// Overflow measurement, shared by lib/render.cjs (Chrome, via page.evaluate) and the editor preview.
// Returns text elements that spill past the slide's padded content box, with overflow in px.
// Must stay self-contained: render.cjs serializes this function into the page.
function measureOverflows(doc) {
  doc = doc || document;
  const slide = doc.querySelector('.slide');
  if (!slide) return [];
  const view = doc.defaultView || window;
  const style = view.getComputedStyle(slide);
  const box = slide.getBoundingClientRect();
  const safe = {
    right: box.right - parseFloat(style.paddingRight),
    bottom: box.bottom - parseFloat(style.paddingBottom)
  };
  const found = [];
  slide.querySelectorAll('h1, h2, .subtitle, li, p, .caption, td, th').forEach((el) => {
    if (el.closest('.brand-mark, .slide-number')) return;
    if (el.parentElement.closest('li, p, td, th') && !el.matches('td, th')) return;
    const r = el.getBoundingClientRect();
    const bottom = Math.round(r.bottom - (el.matches('.caption') ? box.bottom : safe.bottom));
    const right = Math.round(Math.max(r.right, r.left + el.scrollWidth) - safe.right);
    if (bottom > 1 || right > 1) {
      found.push({
        element: el.tagName.toLowerCase() + (el.className ? '.' + el.className : ''),
        text: el.textContent.trim().replace(/\s+/g, ' ').slice(0, 80),
        bottom: Math.max(bottom, 0),
        right: Math.max(right, 0)
      });
    }
  });
  return found;
}

if (typeof module !== 'undefined') module.exports = { measureOverflows };
