const fs = require('fs');
const out = 'D:/Work/WorkBuddy_File/account/design/current/';
const url = 'file:///D:/Work/WorkBuddy_File/account/design/current/fab-options.html';

await page.setViewportSize({ width: 1440, height: 1080 });
await page.goto(url, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

const variants = ['fA', 'fB', 'fC', 'fD'];
const res = [];

for (const v of variants) {
  await page.click('.chip[data-v="' + v + '"]');
  await page.waitForTimeout(350);
  try {
    const buf = await page.locator('#phone').screenshot();
    fs.writeFileSync(out + '_fab-' + v.slice(1).toLowerCase() + '.png', buf);
  } catch (e) {
    await page.screenshot({ path: out + '_fab-' + v.slice(1).toLowerCase() + '.png' });
  }
  const geo = await page.evaluate(() => {
    const phone = document.getElementById('phone');
    const pr = phone.getBoundingClientRect();
    const add = document.getElementById('add').getBoundingClientRect();
    const rows = document.getElementById('rows').getBoundingClientRect();
    const card = document.getElementById('card0').getBoundingClientRect();
    const fab = (sel) => { const r = document.querySelector(sel).getBoundingClientRect(); return +(pr.bottom - r.bottom).toFixed(1); };
    return {
      add: { w: +add.width.toFixed(1), h: +add.height.toFixed(1), topFromBottom: +(pr.bottom - add.top).toFixed(1) },
      rowsBottomFromBottom: +(pr.bottom - rows.bottom).toFixed(1),
      gapRowsToAdd: +(add.top - rows.bottom).toFixed(1),
      cardPadBottom: getComputedStyle(document.getElementById('card0')).paddingBottom,
      layer0Bottom: fab('.lay0'), layer1Bottom: fab('.lay1'), layer2Bottom: fab('.lay2'), layer3Bottom: fab('.lay3'),
      addOverlapsLayerBand: (pr.bottom - add.bottom) < 38,
      gaps: {
        addToScreenEdge: { right: +(pr.width - (add.left - pr.left + add.width)).toFixed(1), bottom: +(pr.bottom - add.bottom).toFixed(1) }
      }
    };
  });
  res.push(Object.assign({ variant: v }, geo));
}

await page.screenshot({ path: out + 'fab-options-full.png', fullPage: true });
return res;
