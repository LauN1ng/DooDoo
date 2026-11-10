await page.setViewportSize({ width: 1700, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/entry-bcd.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(900);

const out = await page.evaluate(() => {
  const res = {};
  const phones = Array.from(document.querySelectorAll('.phone'));
  const s = 1; // 未缩放，直接用 CSS 像素
  phones.forEach((ph, i) => {
    const pr = ph.getBoundingClientRect();
    const rel = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return {
        x: +(r.left - pr.left).toFixed(1), y: +(r.top - pr.top).toFixed(1),
        w: +r.width.toFixed(1), h: +r.height.toFixed(1),
        bottomFrom: +(pr.bottom - r.bottom).toFixed(1), rightFrom: +(pr.right - r.right).toFixed(1)
      };
    };
    const card = ph.querySelector('.lay0');
    const rows = ph.querySelector('.lay0 .rows');
    const lay0 = rel(ph.querySelector('.lay0'));
    const lay1 = rel(ph.querySelector('.lay1'));
    const addrow = rel(ph.querySelector('.addrow'));
    const foot = rel(ph.querySelector('.footbar'));
    const edge = rel(ph.querySelector('.edge'));
    const sheet = rel(ph.querySelector('.sheet'));
    const entry = addrow || foot || edge;
    res['frame' + i] = {
      mode: ph.className.replace('phone ', ''),
      cardH: card ? +card.getBoundingClientRect().height.toFixed(1) : null,
      cardPadBottom: card ? getComputedStyle(card).paddingBottom : null,
      rowsOverflow: rows ? rows.scrollHeight - rows.clientHeight : null,
      entry, lay0, lay1, sheet,
      gapRowsToEntry: (entry && rows) ? +((entry.y) - (rows.getBoundingClientRect().top - pr.top + rows.getBoundingClientRect().height)).toFixed(1) : null,
      entryClearsLayerBand: entry ? entry.bottomFrom >= 38 : null,
      noteTop: (function(){
        const n = ph.querySelector('.note');
        return n ? +(n.getBoundingClientRect().top - pr.top).toFixed(1) : null;
      })(),
      tabBottom: (function(){
        const t = ph.querySelector('.tabx');
        return t ? +((t.getBoundingClientRect().top - pr.top) + t.getBoundingClientRect().height).toFixed(1) : null;
      })()
    };
  });
  return {
    frames: res,
    broken: Array.from(document.images).filter((i) => !i.complete || i.naturalWidth === 0).map((i) => i.getAttribute('src')),
    cells: document.querySelectorAll('.cell').length,
    kb: document.querySelectorAll('.kb button').length
  };
});
return out;
