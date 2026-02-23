export interface ChelperConfig {
    lang: string;
    plan?: 'glm_coding_plan_global' | 'glm_coding_plan_china';
    api_key?: string;
}
export declare class ConfigManager {
    private static instance;
    private configDir;
    private configPath;
    private config;
    private constructor();
    static getInstance(): ConfigManager;
    private ensureConfigDir;
    private loadConfig;
    saveConfig(config?: ChelperConfig): void;
    getConfig(): ChelperConfig;
    updateConfig(updates: Partial<ChelperConfig>): void;
    isFirstRun(): boolean;
    getLang(): string;
    setLang(lang: string): void;
    getPlan(): 'glm_coding_plan_global' | 'glm_coding_plan_china' | undefined;
    setPlan(plan: 'glm_coding_plan_global' | 'glm_coding_plan_china'): void;
    getApiKey(): string | undefined;
    setApiKey(apiKey: string): void;
    revokeApiKey(): void;
}
export declare const configManager: ConfigManager;
