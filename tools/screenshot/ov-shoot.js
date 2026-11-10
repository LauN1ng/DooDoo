const fs = require('fs');
const path = 'file:///D:/Work/WorkBuddy_File/account/design/current/day-overflow.html';
const outDir = 'D:/Work/WorkBuddy_File/account/design/current/';

async function shoot(tag) {
  try {
    await page.screenshot({ path: outDir + '_ov-' + tag + '.png' });
  } catch (e) {
    await page.screenshot({ path: outDir + '_ov-' + tag + '.png' });
  }
}

await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(path, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

const chips = await page.locator('.chip').all();
const tags = ['A', 'B', 'C'];
for (let i = 0; i < chips.length; i++) {
  await chips[i].click();
  await page.waitForTimeout(450);
  await shoot(tags[i]);
}

const geo = await page.evaluate(() => {
  const dev = document.getElementById('dev');
  const card = dev.querySelector('.lay0');
  const cr = card.getBoundingClientRect();
  const pick = (sel) => {
    const el = card.querySelector(sel);
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      clientH: el.clientHeight, scrollH: el.scrollHeight,
      overflowPx: el.scrollHeight - el.clientHeight,
      visible: cs.display === 'none' ? 'hidden' : 'shown'
    };
  };
  const tx = card.querySelector('.tx');
  const out = {
    cardH: +(cr.height).toFixed(1),
    rowH: tx ? +(tx.getBoundingClientRect().height).toFixed(1) : null,
    rowsA: pick('.rowsA'), rowsB: pick('.rowsB'), rowsC: pick('.rowsC'),
    bodyClass: document.body.className
  };
  const rb = card.querySelector('.rowsB');
  if (rb && getComputedStyle(rb).display !== 'none') {
    const rbr = rb.getBoundingClientRect();
    out.rowsBRect = { top: +(rbr.top - cr.top).toFixed(1), h: +rbr.height.toFixed(1), bottomGap: +(cr.bottom - rbr.bottom).toFixed(1) };
  }
  const more = card.querySelector('.moreB');
  if (more && getComputedStyle(more).display !== 'none') {
    const mr = more.getBoundingClientRect();
    out.moreRect = { top: +(mr.top - cr.top).toFixed(1), h: +mr.height.toFixed(1), bottomGap: +(cr.bottom - mr.bottom).toFixed(1), text: more.textContent.trim() };
  }
  const grps = card.querySelectorAll('.grp');
  out.grpCount = grps.length;
  out.grpHeights = Array.from(grps).map(g => +g.getBoundingClientRect().height.toFixed(1));
  const rc = card.querySelector('.rowsC');
  if (rc && getComputedStyle(rc).display !== 'none') {
    out.rowsCInfo = { clientH: rc.clientHeight, scrollH: rc.scrollHeight, overflowPx: rc.scrollHeight - rc.clientHeight };
  }
  return out;
});
return { geo };
