const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/home-m4-v2.html';
await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(1000);
const broken = await page.locator('.ic img').evaluateAll(function (els) {
  return els.filter(function (e) { return !e.complete || e.naturalWidth === 0; })
            .map(function (e) { return e.src; });
});
const check = await page.evaluate(function () {
  const q = function (s) { return document.querySelector(s); };
  return {
    pageBg: getComputedStyle(q('.screen')).backgroundColor,
    fab: getComputedStyle(q('.fab')).backgroundColor,
    navOn: getComputedStyle(q('.nav .t.on')).backgroundColor,
    navBed: getComputedStyle(q('.nav')).backgroundColor,
    card: getComputedStyle(q('.card')).backgroundColor,
    sub: getComputedStyle(q('.ts')).color,
    cards: document.querySelectorAll('.card').length,
    icons: document.querySelectorAll('.ic img').length,
    swatches: document.querySelectorAll('.acc i').length,
    device: (function () { const r = q('.device').getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; })()
  };
});
globalThis.__homeM4 = { brokenImages: broken, check: check };
return await page.screenshot({ fullPage: false });
