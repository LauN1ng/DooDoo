const out = 'D:/Work/WorkBuddy_File/account/design/current/';
await page.setViewportSize({ width: 900, height: 1000 });
await page.goto('file:///D:/Work/WorkBuddy_File/account/design/current/account-detail.html', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(600);
await page.addStyleTag({ content: '*,*::before,*::after{animation:none !important;transition:none !important}' });
await page.waitForTimeout(200);
async function reset(){ await page.evaluate(() => { const sc = document.querySelector('#screen .dtscroll'); if (sc) sc.scrollTop = 0; }); await page.waitForTimeout(120); }
async function shot(n){ await page.locator('#screen').screenshot({ path: out + n + '.png' }); }
async function scrollTo(y){ await page.evaluate((v) => { const sc = document.querySelector('#screen .dtscroll'); if (sc) sc.scrollTop = v; }, y); await page.waitForTimeout(160); }
for (const v of ['G','F']) {
  await page.locator('#pchips .chip[data-p="detail"]').click();
  await page.locator('#vchips .chip[data-v="' + v + '"]').click();
  await page.waitForTimeout(300); await reset();
  await shot('_dt-v4-' + v);
  await scrollTo(400); await shot('_dt-v4-' + v + '-mid');
}
return { ok: true };
