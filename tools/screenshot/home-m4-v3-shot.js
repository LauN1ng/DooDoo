const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/home-m4-v3.html';
await page.setViewportSize({ width: 520, height: 1000 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(600);
await page.locator('.chip[data-n="4"]').click();
await page.waitForTimeout(700);
const broken = await page.locator('.ic img').evaluateAll(function (els) {
  return els.filter(function (e) { return !e.complete || e.naturalWidth === 0; })
            .map(function (e) { return e.src; });
});
const check = await page.evaluate(function () {
  const q = function (s) { return document.querySelector(s); };
  const cs = function (s, p) { return getComputedStyle(q(s))[p]; };
  return {
    pageBg: cs('.screen', 'backgroundColor'),
    cardBg: cs('.card.front', 'backgroundColor'),
    tabSlot: cs('.tabx', 'backgroundColor'),
    addSlot: cs('.addrow .slot', 'backgroundColor'),
    line: cs('.hr', 'backgroundColor'),
    sub: cs('.ts', 'color'),
    expense: cs('.totals .exp', 'color'),
    noteBg: cs('.note', 'backgroundColor'),
    iconBed: cs('.ic', 'backgroundColor'),
    frontShadow: cs('.card.front', 'boxShadow'),
    cards: document.querySelectorAll('.card').length,
    addrows: document.querySelectorAll('.addrow').length,
    icons: document.querySelectorAll('.ic img').length,
    tabWidth: Math.round(q('.tabx').getBoundingClientRect().width),
    tabHeight: Math.round(q('.tabx').getBoundingClientRect().height),
    addrowHeight: Math.round(q('.addrow').getBoundingClientRect().height),
    device: (function () { const r = q('.device').getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; })()
  };
});
globalThis.__homeM4v3 = { brokenImages: broken, check: check };
return await page.screenshot({ fullPage: false });
