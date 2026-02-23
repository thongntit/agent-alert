import { readFileSync, existsSync, readdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
class I18n {
    static instance;
    currentLocale = 'en_US';
    translations = new Map();
    fallbackLocale = 'en_US';
    localesDir;
    constructor() {
        // Determine the locales directory path
        const __filename = fileURLToPath(import.meta.url);
        const __dirname = dirname(__filename);
        // Both in development (src/lib/i18n.ts) and production (dist/lib/i18n.js),
        // locales is at the same relative path: lib -> parent -> locales
        this.localesDir = join(__dirname, '..', 'locales');
        this.loadTranslations();
        this.loadSavedLocale();
    }
    static getInstance() {
        if (!I18n.instance) {
            I18n.instance = new I18n();
        }
        return I18n.instance;
    }
    loadTranslations() {
        try {
            // Check if locales directory exists
            if (!existsSync(this.localesDir)) {
                console.warn(`Locales directory not found at ${this.localesDir}`);
                return;
            }
            // Get all JSON files in the locales directory
            const files = readdirSync(this.localesDir);
            const localeFiles = files.filter(file => file.endsWith('.json'));
            if (localeFiles.length === 0) {
                console.warn('No locale files found in locales directory');
                return;
            }
            // Load each locale file
            for (const file of localeFiles) {
                const locale = file.replace('.json', '');
                const filePath = join(this.localesDir, file);
                try {
                    const fileContent = readFileSync(filePath, 'utf-8');
                    const translations = JSON.parse(fileContent);
                    this.translations.set(locale, translations);
                }
                catch (error) {
                    console.warn(`Failed to load locale file ${file}:`, error);
                }
            }
            // Try to detect locale from environment
            const envLocale = process.env.LANG || process.env.LC_ALL || process.env.LC_MESSAGES;
            if (envLocale) {
                const localeCode = envLocale.split('.')[0].replace('_', '-');
                // First try exact match
                if (this.translations.has(localeCode)) {
                    this.currentLocale = localeCode;
                }
                else {
                    // Try language-only match (e.g., 'en' from 'en-US')
                    const langOnly = localeCode.split('-')[0];
                    const matchingLocale = Array.from(this.translations.keys()).find(key => key.startsWith(langOnly + '_'));
                    if (matchingLocale) {
                        this.currentLocale = matchingLocale;
                    }
                    else if (langOnly === 'zh') {
                        // Fallback to zh_CN for Chinese
                        this.currentLocale = 'zh_CN';
                    }
                    else if (langOnly === 'en') {
                        // Fallback to en_US for English
                        this.currentLocale = 'en_US';
                    }
                }
            }
        }
        catch (error) {
            console.warn('Failed to load translations:', error);
        }
    }
    setLocale(locale) {
        if (this.translations.has(locale)) {
            this.currentLocale = locale;
            this.saveLocale();
        }
        else {
            console.warn(`Locale '${locale}' not supported, falling back to '${this.currentLocale}'`);
        }
    }
    getLocale() {
        return this.currentLocale;
    }
    getAvailableLocales() {
        return Array.from(this.translations.keys());
    }
    translate(key, params) {
        const keys = key.split('.');
        let translation = this.translations.get(this.currentLocale);
        for (const k of keys) {
            if (translation && typeof translation === 'object' && k in translation) {
                translation = translation[k];
            }
            else {
                // Fallback to fallback locale
                translation = this.translations.get(this.fallbackLocale);
                for (const fallbackKey of keys) {
                    if (translation && typeof translation === 'object' && fallbackKey in translation) {
                        translation = translation[fallbackKey];
                    }
                    else {
                        return key; // Return key if translation not found
                    }
                }
                break;
            }
        }
        if (typeof translation !== 'string') {
            return key;
        }
        // Replace parameters in the translation string
        if (params) {
            return translation.replace(/\{\{(\w+)\}\}/g, (match, param) => {
                return params[param] || match;
            });
        }
        return translation;
    }
    t(key, params) {
        return this.translate(key, params);
    }
    saveLocale() {
        // Language is now saved via ConfigManager
        // This method is kept for compatibility
    }
    loadSavedLocale() {
        // Language is now loaded via ConfigManager
        // This method is kept for compatibility
    }
    loadFromConfig(locale) {
        if (this.translations.has(locale)) {
            this.currentLocale = locale;
        }
    }
}
export const i18n = I18n.getInstance();
export { i18n as I18n };
