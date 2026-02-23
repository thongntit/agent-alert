export interface MarketplaceInfo {
    source: {
        source: string;
        path: string;
    };
    installLocation: string;
    lastUpdated: string;
}
export interface KnownMarketplaces {
    [key: string]: MarketplaceInfo;
}
export interface PluginInfo {
    name: string;
    source: string;
    category: string;
    description: string;
}
export interface MarketplaceConfig {
    $schema?: string;
    name: string;
    version: string;
    description: string;
    owner: {
        name: string;
        email: string;
    };
    plugins: PluginInfo[];
}
export interface InstalledPluginEntry {
    scope: string;
    installPath: string;
    version: string;
    installedAt: string;
    lastUpdated: string;
    gitCommitSha?: string;
    isLocal?: boolean;
}
export interface InstalledPluginsConfig {
    version: number;
    plugins: {
        [key: string]: InstalledPluginEntry[];
    };
}
export interface ClaudeSettings {
    env?: Record<string, string>;
    enabledPlugins?: Record<string, boolean>;
    [key: string]: any;
}
export interface PluginStatus {
    name: string;
    category: string;
    description: string;
    isInstalled: boolean;
    isEnabled: boolean;
    fullName: string;
}
export declare class PluginMarketplaceManager {
    private static instance;
    private knownMarketplacesPath;
    private installedPluginsPath;
    private settingsPath;
    private bundledPluginsDir;
    private constructor();
    static getInstance(): PluginMarketplaceManager;
    /**
     * Get the bundled plugins directory path
     */
    getBundledPluginsDir(): string;
    /**
     * Read known marketplaces configuration
     */
    getKnownMarketplaces(): KnownMarketplaces;
    /**
     * Check if a marketplace is installed
     */
    isMarketplaceInstalled(marketplaceName: string): boolean;
    /**
     * Get marketplace info
     */
    getMarketplaceInfo(marketplaceName: string): MarketplaceInfo | null;
    /**
     * Install marketplace using claude CLI
     */
    installMarketplace(pluginDir: string): boolean;
    /**
     * Read marketplace.json from a marketplace directory
     */
    readMarketplaceConfig(marketplaceDir: string): MarketplaceConfig | null;
    /**
     * Get installed plugins configuration
     */
    getInstalledPlugins(): InstalledPluginsConfig;
    /**
     * Get Claude settings (for enabledPlugins)
     */
    getClaudeSettings(): ClaudeSettings;
    /**
     * Check if a plugin is installed
     */
    isPluginInstalled(pluginName: string, marketplaceName: string): boolean;
    /**
     * Check if a plugin is enabled
     */
    isPluginEnabled(pluginName: string, marketplaceName: string): boolean;
    /**
     * Get plugin status list for a marketplace
     */
    getPluginsStatus(marketplaceName: string, plugins: PluginInfo[]): PluginStatus[];
    /**
     * Install a plugin using claude CLI
     */
    installPlugin(pluginFullName: string): boolean;
    /**
     * Uninstall a plugin using claude CLI
     */
    uninstallPlugin(pluginFullName: string): boolean;
    /**
     * Enable a plugin using claude CLI
     */
    enablePlugin(pluginFullName: string): boolean;
    /**
     * Disable a plugin using claude CLI
     */
    disablePlugin(pluginFullName: string): boolean;
    /**
     * Update a plugin using claude CLI
     */
    updatePlugin(pluginFullName: string): boolean;
}
export declare const pluginMarketplaceManager: PluginMarketplaceManager;
