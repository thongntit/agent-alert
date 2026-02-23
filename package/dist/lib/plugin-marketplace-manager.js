import { existsSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { logger } from '../utils/logger.js';
export class PluginMarketplaceManager {
    static instance;
    knownMarketplacesPath;
    installedPluginsPath;
    settingsPath;
    bundledPluginsDir;
    constructor() {
        const claudeDir = join(homedir(), '.claude');
        this.knownMarketplacesPath = join(claudeDir, 'plugins', 'known_marketplaces.json');
        this.installedPluginsPath = join(claudeDir, 'plugins', 'installed_plugins.json');
        this.settingsPath = join(claudeDir, 'settings.json');
        // Get the bundled plugins directory from the package
        const __filename = fileURLToPath(import.meta.url);
        const __dirname = dirname(__filename);
        // Both in development (src/lib/) and production (dist/lib/),
        // zai-coding-plugins is at the package root
        this.bundledPluginsDir = join(__dirname, '..', '..', 'zai-coding-plugins');
    }
    static getInstance() {
        if (!PluginMarketplaceManager.instance) {
            PluginMarketplaceManager.instance = new PluginMarketplaceManager();
        }
        return PluginMarketplaceManager.instance;
    }
    /**
     * Get the bundled plugins directory path
     */
    getBundledPluginsDir() {
        return this.bundledPluginsDir;
    }
    /**
     * Read known marketplaces configuration
     */
    getKnownMarketplaces() {
        try {
            if (existsSync(this.knownMarketplacesPath)) {
                const content = readFileSync(this.knownMarketplacesPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.getKnownMarketplaces', error);
        }
        return {};
    }
    /**
     * Check if a marketplace is installed
     */
    isMarketplaceInstalled(marketplaceName) {
        const marketplaces = this.getKnownMarketplaces();
        return marketplaceName in marketplaces;
    }
    /**
     * Get marketplace info
     */
    getMarketplaceInfo(marketplaceName) {
        const marketplaces = this.getKnownMarketplaces();
        return marketplaces[marketplaceName] || null;
    }
    /**
     * Install marketplace using claude CLI
     */
    installMarketplace(pluginDir) {
        try {
            // Use relative path to avoid Windows absolute path issues
            // Claude CLI doesn't recognize Windows paths like C:\...
            execSync('claude plugin marketplace add ./', {
                stdio: 'pipe',
                encoding: 'utf-8',
                cwd: pluginDir
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.installMarketplace', error);
            return false;
        }
    }
    /**
     * Read marketplace.json from a marketplace directory
     */
    readMarketplaceConfig(marketplaceDir) {
        try {
            const marketplaceJsonPath = join(marketplaceDir, '.claude-plugin', 'marketplace.json');
            if (existsSync(marketplaceJsonPath)) {
                const content = readFileSync(marketplaceJsonPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.readMarketplaceConfig', error);
        }
        return null;
    }
    /**
     * Get installed plugins configuration
     */
    getInstalledPlugins() {
        try {
            if (existsSync(this.installedPluginsPath)) {
                const content = readFileSync(this.installedPluginsPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.getInstalledPlugins', error);
        }
        return { version: 1, plugins: {} };
    }
    /**
     * Get Claude settings (for enabledPlugins)
     */
    getClaudeSettings() {
        try {
            if (existsSync(this.settingsPath)) {
                const content = readFileSync(this.settingsPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.getClaudeSettings', error);
        }
        return {};
    }
    /**
     * Check if a plugin is installed
     */
    isPluginInstalled(pluginName, marketplaceName) {
        const installedPlugins = this.getInstalledPlugins();
        const fullName = `${pluginName}@${marketplaceName}`;
        return fullName in installedPlugins.plugins;
    }
    /**
     * Check if a plugin is enabled
     */
    isPluginEnabled(pluginName, marketplaceName) {
        const settings = this.getClaudeSettings();
        const fullName = `${pluginName}@${marketplaceName}`;
        return settings.enabledPlugins?.[fullName] === true;
    }
    /**
     * Get plugin status list for a marketplace
     */
    getPluginsStatus(marketplaceName, plugins) {
        return plugins.map(plugin => ({
            name: plugin.name,
            category: plugin.category,
            description: plugin.description,
            isInstalled: this.isPluginInstalled(plugin.name, marketplaceName),
            isEnabled: this.isPluginEnabled(plugin.name, marketplaceName),
            fullName: `${plugin.name}@${marketplaceName}`
        }));
    }
    /**
     * Install a plugin using claude CLI
     */
    installPlugin(pluginFullName) {
        try {
            execSync(`claude plugin install ${pluginFullName}`, {
                stdio: 'pipe',
                encoding: 'utf-8'
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.installPlugin', error);
            return false;
        }
    }
    /**
     * Uninstall a plugin using claude CLI
     */
    uninstallPlugin(pluginFullName) {
        try {
            execSync(`claude plugin uninstall ${pluginFullName}`, {
                stdio: 'pipe',
                encoding: 'utf-8'
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.uninstallPlugin', error);
            return false;
        }
    }
    /**
     * Enable a plugin using claude CLI
     */
    enablePlugin(pluginFullName) {
        try {
            execSync(`claude plugin enable ${pluginFullName}`, {
                stdio: 'pipe',
                encoding: 'utf-8'
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.enablePlugin', error);
            return false;
        }
    }
    /**
     * Disable a plugin using claude CLI
     */
    disablePlugin(pluginFullName) {
        try {
            execSync(`claude plugin disable ${pluginFullName}`, {
                stdio: 'pipe',
                encoding: 'utf-8'
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.disablePlugin', error);
            return false;
        }
    }
    /**
     * Update a plugin using claude CLI
     */
    updatePlugin(pluginFullName) {
        try {
            execSync(`claude plugin update ${pluginFullName}`, {
                stdio: 'pipe',
                encoding: 'utf-8'
            });
            return true;
        }
        catch (error) {
            console.log(error);
            logger.logError('PluginMarketplaceManager.updatePlugin', error);
            return false;
        }
    }
}
export const pluginMarketplaceManager = PluginMarketplaceManager.getInstance();
