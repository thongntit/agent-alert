import { MCPService } from './mcp-manager.js';
export interface FactoryDroidModelConfig {
    displayName: string;
    model: string;
    baseUrl: string;
    apiKey: string;
    provider: string;
    maxOutputTokens: number;
}
export interface FactoryDroidConfig {
    customModels?: FactoryDroidModelConfig[];
    [key: string]: any;
}
export interface FactoryDroidMCPServerConfig {
    type: 'stdio' | 'http';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
    url?: string;
    headers?: Record<string, string>;
    disabled?: boolean;
}
export interface FactoryDroidMCPConfig {
    mcpServers?: Record<string, FactoryDroidMCPServerConfig>;
    [key: string]: any;
}
export declare class FactoryDroidManager {
    private static instance;
    private configPath;
    private mcpConfigPath;
    private constructor();
    static getInstance(): FactoryDroidManager;
    /**
     * 确保配置目录存在
     */
    private ensureConfigDir;
    /**
     * 读取主配置
     */
    getConfig(): FactoryDroidConfig;
    /**
     * 保存主配置
     */
    saveConfig(config: FactoryDroidConfig): void;
    /**
     * 读取 MCP 配置
     */
    getMCPConfig(): FactoryDroidMCPConfig;
    /**
     * 保存 MCP 配置
     */
    saveMCPConfig(config: FactoryDroidMCPConfig): void;
    /**
     * 获取 baseUrl（根据套餐类型和协议）
     */
    private getBaseUrl;
    /**
     * 获取 displayName（根据套餐类型和协议）
     */
    private getDisplayName;
    /**
     * 加载 GLM Coding Plan 配置到 Factory Droid
     */
    loadGLMConfig(plan: 'glm_coding_plan_global' | 'glm_coding_plan_china', apiKey: string): void;
    /**
     * 卸载 GLM Coding Plan 配置
     */
    unloadGLMConfig(): void;
    /**
     * 检查 MCP 服务是否已安装
     */
    isMCPInstalled(mcpId: string): boolean;
    /**
     * 安装 MCP 服务
     */
    installMCP(mcp: MCPService, apiKey?: string, plan?: 'glm_coding_plan_global' | 'glm_coding_plan_china'): void;
    /**
     * 卸载 MCP 服务
     */
    uninstallMCP(mcpId: string): void;
    /**
     * 获取已安装的 MCP 服务列表
     */
    getInstalledMCPs(): string[];
    /**
     * 获取所有 MCP 服务的安装状态
     */
    getMCPStatus(mcpServices: MCPService[]): Map<string, boolean>;
    /**
     * 获取非内置的 MCP 服务列表
     */
    getOtherMCPs(builtinIds: string[]): Array<{
        id: string;
        config: FactoryDroidMCPServerConfig;
    }>;
    /**
     * 获取所有 MCP 服务器配置
     */
    getAllMCPServers(): Record<string, FactoryDroidMCPServerConfig>;
    /**
     * 检测当前 Factory Droid 配置的套餐和 API Key
     */
    detectCurrentConfig(): {
        plan: 'glm_coding_plan_global' | 'glm_coding_plan_china' | null;
        apiKey: string | null;
    };
}
export declare const factoryDroidManager: FactoryDroidManager;
