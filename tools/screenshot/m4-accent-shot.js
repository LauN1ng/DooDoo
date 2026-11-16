const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/m4-accent.html';
await page.setViewportSize({ width: 1100, height: 2200 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(1000);
const panels = await page.locator('.panel').count();
const broken = await page.locator('.ic img').evaluateAll(function (els) {
  return els.filter(function (e) { return !e.complete || e.naturalWidth === 0; })
            .map(function (e) { return e.src; });
});
const check = await page.locator('.panel').evaluateAll(function (ps) {
  return ps.map(function (p) {
    return {
      k: p.querySelector('.k').textContent,
      accent: getComputedStyle(p.querySelector('.cta')).backgroundColor,
      page: getComputedStyle(p.querySelector('.screen')).backgroundColor,
      inset: getComputedStyle(p.querySelector('.ic')).backgroundColor,
      sub: getComputedStyle(p.querySelector('.ts')).color
    };
  });
});
const docHeight = await page.evaluate(function () { return document.documentElement.scrollHeight; });
await page.setViewportSize({ width: 1100, height: docHeight + 20 });
await page.waitForTimeout(300);
globalThis.__m4accent = { panels: panels, brokenImages: broken, check: check, docHeight: docHeight };
return await page.screenshot({ fullPage: false });
