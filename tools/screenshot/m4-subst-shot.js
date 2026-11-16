const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/m4-subst-2026-11-16.html';
await page.setViewportSize({ width: 640, height: 900 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(600);
const broken = await page.locator('.catrow img').evaluateAll(function (els) {
  return els.filter(function (e) { return !e.complete || e.naturalWidth === 0; })
            .map(function (e) { return e.src.slice(0, 40); });
});
const docHeight = await page.evaluate(function () { return document.documentElement.scrollHeight; });
globalThis.__shot = { broken: broken, docHeight: docHeight };
return await page.screenshot({ fullPage: true });
