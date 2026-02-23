declare class I18n {
    private static instance;
    private currentLocale;
    private translations;
    private fallbackLocale;
    private localesDir;
    private constructor();
    static getInstance(): I18n;
    private loadTranslations;
    setLocale(locale: string): void;
    getLocale(): string;
    getAvailableLocales(): string[];
    translate(key: string, params?: Record<string, string>): string;
    t(key: string, params?: Record<string, string>): string;
    private saveLocale;
    private loadSavedLocale;
    loadFromConfig(locale: string): void;
}
export declare const i18n: I18n;
export { i18n as I18n };
