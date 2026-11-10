const fs = require('fs');
const path = 'file:///D:/Work/WorkBuddy_File/account/design/current/nav-final.html';
const outDir = 'D:/Work/WorkBuddy_File/account/design/current/';

async function shoot(tag) {
  try {
    await page.screenshot({ path: outDir + '_nav-' + tag + '.png' });
  } catch (e) {
    await page.screenshot({ path: outDir + '_nav-' + tag + '.png' });
  }
}

await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(path, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);

const chips = await page.locator('.chip').all();
const tags = ['A', 'B', 'C'];
for (let i = 0; i < chips.length; i++) {
  await chips[i].click();
  await page.waitForTimeout(500);
  await shoot(tags[i]);
}

// 读回几何：验证三版控件位置与层厚带是否被遮
const geo = await page.evaluate(() => {
  const out = {};
  const dev = document.getElementById('dev');
  const sr = dev.getBoundingClientRect();
  const s = sr.width / 390;
  const q = (sel) => {
    const el = dev.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { left: +(r.left - sr.left).toFixed(1), right: +(r.right - sr.left).toFixed(1), top: +(r.top - sr.top).toFixed(1), bottom: +(sr.bottom - r.bottom).toFixed(1), w: +(r.width).toFixed(1), h: +(r.height).toFixed(1) };
  };
  out.lay0 = q('.lay0');
  out.lay1 = q('.lay1');
  out.lay2 = q('.lay2');
  out.lay3 = q('.lay3');
  out.navA = q('.navA');
  out.fabA = q('.fabA');
  out.navC = q('.navC');
  out.seg = q('.seg');
  out.segVisible = getComputedStyle(dev.querySelector('.seg')).display;
  out.bodyClass = document.body.className;
  return out;
});

const errs = await page.evaluate(() => (window.__errs || []).slice(0, 5));
return { geo, errs };
