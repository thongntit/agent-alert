import { configManager } from '../lib/config.js';
import { i18n } from '../lib/i18n.js';
import chalk from 'chalk';
export async function langCommand(args) {
    if (args.length === 0 || args[0] === 'show') {
        // Show current language
        const currentLang = configManager.getLang();
        console.log(`${i18n.t('lang.current')}: ${chalk.cyan(currentLang)}`);
        console.log(`${i18n.t('lang.available')}: ${i18n.getAvailableLocales().join(', ')}`);
        return;
    }
    if (args[0] === 'set' && args.length >= 2) {
        const newLang = args[1];
        const availableLocales = i18n.getAvailableLocales();
        if (!availableLocales.includes(newLang)) {
            console.error(chalk.red(i18n.t('lang.invalid', { lang: newLang })));
            console.log(`${i18n.t('lang.available')}: ${availableLocales.join(', ')}`);
            return;
        }
        const oldLang = configManager.getLang();
        configManager.setLang(newLang);
        i18n.loadFromConfig(newLang);
        console.log(chalk.green(i18n.t('lang.changed', { from: oldLang, to: newLang })));
        return;
    }
    // Show usage
    console.log(i18n.t('lang.show_usage'));
    console.log(i18n.t('lang.set_usage'));
}
