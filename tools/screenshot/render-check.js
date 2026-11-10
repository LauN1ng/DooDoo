const out = 'D:/Work/WorkBuddy_File/account/design/current/';
const base = 'file:///D:/Work/WorkBuddy_File/account/design/current/';
const targets = [
  ['index.html', '_v-index.png'],
  ['home-final.html', '_v-home.png'],
  ['account-stack-v1.0.html', '_v-frozen.png']
];

await page.setViewportSize({ width: 520, height: 1000 });
const res = [];

for (const [f, p] of targets) {
  await page.goto(base + f, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);
  const probe = await page.evaluate(() => {
    const imgs = Array.from(document.images);
    const broken = imgs.filter(i => !i.complete || i.naturalWidth === 0).map(i => i.getAttribute('src'));
    const screen = document.querySelector('.screen') || document.body;
    const sr = screen.getBoundingClientRect();
    const backgrounds = Array.from(document.querySelectorAll('*'))
      .map(el => getComputedStyle(el).backgroundImage)
      .filter(v => v && v !== 'none' && v.includes('url('));
    return {
      title: document.title,
      imgCount: imgs.length,
      broken,
      screen: { w: +sr.width.toFixed(1), h: +sr.height.toFixed(1) },
      bgImageCount: backgrounds.length,
      sampleBg: backgrounds.slice(0, 3)
    };
  });
  try {
    await page.screenshot({ path: out + p });
  } catch (e) {
    await page.screenshot({ path: out + p });
  }
  res.push(Object.assign({ file: f }, probe));
}

return res;
