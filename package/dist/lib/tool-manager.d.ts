export interface ToolInfo {
    name: string;
    command: string;
    installCommand: string;
    configPath: string;
    displayName: string;
    hidden?: boolean;
}
export declare const SUPPORTED_TOOLS: Record<string, ToolInfo>;
export declare class ToolManager {
    private static instance;
    private constructor();
    static getInstance(): ToolManager;
    isToolInstalled(toolName: string): boolean;
    installTool(toolName: string): Promise<void>;
    getToolConfig(toolName: string): any;
    updateToolConfig(toolName: string, config: any): void;
    loadGLMConfig(toolName: string, plan: 'glm_coding_plan_global' | 'glm_coding_plan_china', apiKey: string): void;
    getInstalledTools(): string[];
    getSupportedTools(): ToolInfo[];
    isGitInstalled(): boolean;
}
export declare const toolManager: ToolManager;
