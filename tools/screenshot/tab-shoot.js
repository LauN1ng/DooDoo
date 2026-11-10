const fs = require('fs');
const out = 'D:/Work/WorkBuddy_File/account/design/current/';
const url = 'file:///D:/Work/WorkBuddy_File/account/design/current/tab-top.html';

await page.setViewportSize({ width: 1440, height: 1080 });
await page.goto(url, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

async function shotDevice(tag){
  try {
    const buf = await page.locator('#phone').screenshot();
    fs.writeFileSync(out + '_tab-' + tag + '.png', buf);
  } catch (e) {
    await page.screenshot({ path: out + '_tab-' + tag + '.png' });
  }
}

const variants = ['t1', 't2', 't3'];
for (const v of variants) {
  await page.click('.chip[data-v="' + v + '"]');
  await page.waitForTimeout(350);
  await shotDevice(v);
}

// 回到 T1 并打开标注
await page.click('.chip[data-v="t1"]');
await page.check('#annoChk');
await page.waitForTimeout(300);
await shotDevice('t1-anno');

try {
  await page.screenshot({ path: out + 'tab-top-full.png', fullPage: true });
} catch (e) {
  await page.screenshot({ path: out + 'tab-top-full.png', fullPage: true });
}

const geo = await page.evaluate(() => {
  const phone = document.getElementById('phone');
  const pr = phone.getBoundingClientRect();
  const g = (sel) => {
    const el = phone.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return {
      x: +(r.left - pr.left).toFixed(1), y: +(r.top - pr.top).toFixed(1),
      w: +r.width.toFixed(1), h: +r.height.toFixed(1),
      bottomFromScreen: +(pr.bottom - r.bottom).toFixed(1),
      rightFromScreen: +(pr.right - r.right).toFixed(1)
    };
  };
  const tabx = g('#tabx');
  const logo = g('.hd .logo');
  const hd = g('.hd');
  const deck = g('.deck');
  const lay0 = g('.lay0'), lay1 = g('.lay1'), lay2 = g('.lay2'), lay3 = g('.lay3');
  const rows = g('.lay0 .rows');
  const fab = g('.fab');
  const cardPadBottom = getComputedStyle(phone.querySelector('.lay0')).paddingBottom;
  return {
    screen: { w: +pr.width.toFixed(1), h: +pr.height.toFixed(1) },
    tabx, logo, hd, deck, lay0, lay1, lay2, lay3, rows, fab, cardPadBottom,
    gapLogoToTab: tabx && logo ? +(tabx.x - (logo.x + logo.w)).toFixed(1) : null,
    tabRightInset: tabx ? +(pr.width - (tabx.x + tabx.w)).toFixed(1) : null,
    rowsToFabGap: rows && fab ? +(fab.y - (rows.y + rows.h)).toFixed(1) : null,
    layerThickness: lay0 && lay1 ? +(lay0.bottomFromScreen - lay1.bottomFromScreen).toFixed(1) : null,
    tabWidth: tabx ? tabx.w : null
  };
});

return geo;
