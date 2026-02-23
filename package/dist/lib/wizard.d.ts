import { PluginStatus } from './plugin-marketplace-manager.js';
export declare class Wizard {
    private static instance;
    private readonly BOX_WIDTH;
    private constructor();
    static getInstance(): Wizard;
    /**
     * Create a simple box with title using double-line border style
     */
    private createBox;
    /**
     * Display operation hints
     */
    private showOperationHints;
    /**
     * Prompt wrapper that shows operation hints
     */
    private promptWithHints;
    private printBanner;
    private resetScreen;
    runFirstTimeSetup(): Promise<void>;
    configLanguage(): Promise<void>;
    configPlan(): Promise<void>;
    configApiKey(): Promise<void>;
    selectAndConfigureTool(): Promise<void>;
    configureTool(toolName: string): Promise<void>;
    showMainMenu(): Promise<void>;
    showToolMenu(toolName: string): Promise<void>;
    startTool(toolName: string): Promise<void>;
    loadGLMConfig(toolName: string): Promise<void>;
    unloadGLMConfig(toolName: string): Promise<void>;
    showMCPMenu(toolName: string): Promise<void>;
    showPluginMarketplace(): Promise<void>;
    showPluginDetail(plugin: PluginStatus, marketplaceName: string): Promise<void>;
    showMCPDetail(toolName: string, mcpId: string): Promise<void>;
    showOtherMCPDetail(toolName: string, mcpId: string): Promise<void>;
    installAllPresetMCPs(toolName: string): Promise<void>;
}
export declare const wizard: Wizard;
