await page.setViewportSize({ width: 1200, height: 1000 });
await page.goto('https://apps.apple.com/cn/app/id1473785373', { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(2000);
await page.evaluate(() => window.scrollTo(0, 900));
await page.waitForTimeout(1500);
const info = await page.evaluate(() => {
  const imgs = Array.from(document.querySelectorAll('img'));
  const all = imgs.map((i) => ({
    host: (i.currentSrc || i.src || '').split('/')[2] || '(none)',
    src: (i.currentSrc || i.src || '').slice(0, 120),
    w: i.naturalWidth, h: i.naturalHeight
  }));
  const sources = Array.from(document.querySelectorAll('source')).map((s) => (s.srcset || '').slice(0, 150));
  const bg = Array.from(document.querySelectorAll('*'))
    .map((el) => getComputedStyle(el).backgroundImage)
    .filter((v) => v && v.includes('url(') && /mzstatic|apple/.test(v)).slice(0, 8);
  return { title: document.title, all: all.slice(0, 25), sources: sources.slice(0, 8), bg };
});
return info;
