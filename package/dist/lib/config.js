import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import * as yaml from 'js-yaml';
import { logger } from '../utils/logger.js';
export class ConfigManager {
    static instance;
    configDir;
    configPath;
    config;
    constructor() {
        // chelper 配置文件路径（跨平台支持）
        // - macOS/Linux: ~/.chelper/config.yaml
        // - Windows: %USERPROFILE%\.chelper\config.yaml
        //   (例如: C:\Users\username\.chelper\config.yaml)
        this.configDir = join(homedir(), '.chelper');
        this.configPath = join(this.configDir, 'config.yaml');
        this.config = this.loadConfig();
    }
    static getInstance() {
        if (!ConfigManager.instance) {
            ConfigManager.instance = new ConfigManager();
        }
        return ConfigManager.instance;
    }
    ensureConfigDir() {
        if (!existsSync(this.configDir)) {
            mkdirSync(this.configDir, { recursive: true });
        }
    }
    loadConfig() {
        try {
            if (existsSync(this.configPath)) {
                const fileContent = readFileSync(this.configPath, 'utf-8');
                const config = yaml.load(fileContent);
                return config || { lang: 'en_US' };
            }
        }
        catch (error) {
            console.warn('Failed to load config, using defaults:', error);
            logger.logError('ConfigManager.loadConfig', error);
        }
        return { lang: 'en_US' };
    }
    saveConfig(config) {
        try {
            this.ensureConfigDir();
            const configToSave = config || this.config;
            const yamlContent = yaml.dump(configToSave);
            writeFileSync(this.configPath, yamlContent, 'utf-8');
            this.config = configToSave;
        }
        catch (error) {
            console.error('Failed to save config:', error);
            logger.logError('ConfigManager.saveConfig', error);
            throw error;
        }
    }
    getConfig() {
        return { ...this.config };
    }
    updateConfig(updates) {
        this.config = { ...this.config, ...updates };
        this.saveConfig();
    }
    isFirstRun() {
        return !existsSync(this.configPath);
    }
    getLang() {
        return this.config.lang || 'en_US';
    }
    setLang(lang) {
        this.updateConfig({ lang });
    }
    getPlan() {
        return this.config.plan;
    }
    setPlan(plan) {
        this.updateConfig({ plan });
    }
    getApiKey() {
        return this.config.api_key;
    }
    setApiKey(apiKey) {
        this.updateConfig({ api_key: apiKey });
    }
    revokeApiKey() {
        this.updateConfig({ api_key: undefined });
    }
}
export const configManager = ConfigManager.getInstance();
