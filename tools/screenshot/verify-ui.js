// 交互自检：不截图，只验证脚本无异常、控件的几何与文案随切换更新
const out = {};

await page.setViewportSize({ width: 1200, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/tab-top.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(600);
await page.check('#annoChk');
for (const v of ['t2', 't3', 't1']) {
  await page.click('.chip[data-v="' + v + '"]', { timeout: 5000 });
  await page.waitForTimeout(200);
}
out.tabTop = await page.evaluate(() => {
  const phone = document.getElementById('phone');
  const pr = phone.getBoundingClientRect();
  const tab = document.getElementById('tabx').getBoundingClientRect();
  const tag = document.getElementById('tW');
  const box = document.getElementById('gTab');
  return {
    variant: phone.className,
    tab: { w: +tab.width.toFixed(1), h: +tab.height.toFixed(1), rightInset: +(pr.right - tab.right).toFixed(1) },
    annoVisible: getComputedStyle(document.getElementById('anno')).display,
    annoBox: box ? { w: +box.getBoundingClientRect().width.toFixed(1) } : null,
    annoText: tag ? tag.textContent : null,
    panelTitle: document.getElementById('pTitle').textContent,
    stripCards: document.querySelectorAll('.mini').length,
    broken: Array.from(document.images).filter((i) => !i.complete || i.naturalWidth === 0).length
  };
});

await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/home-v2.html', { waitUntil: 'domcontentloaded', timeout: 20000 });
await page.waitForTimeout(600);
const fab = {};
for (const v of ['fA', 'fB', 'fC', 'fD']) {
  await page.click('.chip[data-v="' + v + '"]', { timeout: 5000 });
  await page.waitForTimeout(200);
  fab[v] = await page.evaluate(() => {
    const scr = document.getElementById('screen');
    const sr = scr.getBoundingClientRect();
    const s = sr.width / 390;
    const add = document.getElementById('add').getBoundingClientRect();
    const rows = document.querySelector('.lay0 .rows').getBoundingClientRect();
    return {
      cls: scr.className,
      add: { w: +(add.width / s).toFixed(1), h: +(add.height / s).toFixed(1), bottomFrom: +((sr.bottom - add.bottom) / s).toFixed(1) },
      gap: +((add.top - rows.bottom) / s).toFixed(1),
      pad: getComputedStyle(document.querySelector('.lay0')).paddingBottom
    };
  });
}
out.homeV2 = fab;

// 顶部 tab 点击不应报错
await page.click('.tabx .t[data-tab="assets"]', { timeout: 5000 });
await page.waitForTimeout(600);
out.toast = await page.evaluate(() => ({
  on: document.getElementById('toast').classList.contains('on'),
  text: document.getElementById('toast').textContent
}));

return out;
