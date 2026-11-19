const { remote } = require('webdriverio');
const fs = require('fs');
const { execFileSync } = require('child_process');

const SCREENSHOT_DIR = './screenshots';
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

const capabilities = {
  platformName: 'Android',
  'appium:deviceName': 'emulator-5554',
  'appium:automationName': 'UiAutomator2',
  'appium:noReset': true,
  'appium:dontStopAppOnReset': true,
  'appium:autoGrantPermissions': true,
  'appium:systemPort': 8200,
  'appium:uiautomator2ServerInstallTimeout': 120000,
  'appium:uiautomator2ServerLaunchTimeout': 120000,
  'appium:androidInstallTimeout': 120000,
  'appium:adbExecTimeout': 120000,
  'appium:newCommandTimeout': 60,
};

async function createDriver() {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      console.log(`Connecting to Appium (attempt ${attempt}/3)...`);
      return await remote({
        protocol: 'http',
        hostname: '127.0.0.1',
        port: 4723,
        path: '/',
        capabilities,
        logLevel: 'warn',
      });
    } catch (error) {
      lastError = error;
      console.error(`Appium session attempt ${attempt} failed: ${error.message || error}`);
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
  throw lastError;
}

async function saveScreenshot(driver, filename) {
  try {
    await driver.saveScreenshot(`${SCREENSHOT_DIR}/${filename}`);
    console.log(`Screenshot saved: ${filename}`);
  } catch (e) {
    console.error(`Could not save screenshot ${filename}:`, e.message);
  }
}

(async () => {
  let driver;
  try {
    execFileSync('adb', [
      'shell',
      'am',
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      'https://play.google.com/store/search?q=Instagram&c=apps',
    ], { stdio: 'inherit' });

    driver = await createDriver();
    console.log('Session created');

    const activity = await driver.getCurrentActivity();
    const pkg = await driver.getCurrentPackage();
    console.log(`Current app: ${pkg} / ${activity}`);
    if (!pkg) throw new Error('Unable to read the current Android package');

    await driver.pause(3000);
    await saveScreenshot(driver, 'screenshot_1_launch.png');
    await saveScreenshot(driver, 'screenshot_2_search.png');
    fs.writeFileSync(`${SCREENSHOT_DIR}/page_source_results.xml`, await driver.getPageSource());

    await saveScreenshot(driver, 'screenshot_3_final.png');
    console.log('Test complete: Play Store Instagram search opened!');

  } catch (err) {
    console.error('Test error:', err.message || err);
    if (driver) await saveScreenshot(driver, 'screenshot_error.png');
    process.exitCode = 1;
  } finally {
    if (driver) {
      try { await driver.deleteSession(); } catch (_) {}
    }
  }
})();
///
