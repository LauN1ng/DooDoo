const target = 'file:///D:/Work/WorkBuddy_File/account/design/current/m4-tokens.html';
await page.setViewportSize({ width: 1100, height: 1000 });
await page.goto(target, { waitUntil: 'load' });
await page.waitForTimeout(1000);
const panels = await page.locator('.panel').count();
const broken = await page.locator('.ic img').evaluateAll(function (els) {
  return els.filter(function (e) { return !e.complete || e.naturalWidth === 0; })
            .map(function (e) { return e.src; });
});
const pageColors = await page.locator('.screen').evaluateAll(function (els) {
  return els.map(function (e) { return getComputedStyle(e).backgroundColor; });
});
const docHeight = await page.evaluate(function () { return document.documentElement.scrollHeight; });
const subColors = await page.locator('.ts').evaluateAll(function (els) {
  return els.slice(0, 6).map(function (e) { return getComputedStyle(e).color; });
});
globalThis.__m4check = {
  panels: panels,
  brokenImages: broken,
  pageColors: pageColors,
  docHeight: docHeight,
  subColors: subColors
};
return await page.screenshot({ fullPage: true });
