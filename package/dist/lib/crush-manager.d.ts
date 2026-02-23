import { MCPService } from './mcp-manager.js';
export interface CrushProviderConfig {
    id: string;
    name: string;
    base_url: string;
    api_key: string;
}
export interface CrushMCPServerConfig {
    type: 'stdio' | 'http' | 'sse';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
    url?: string;
    headers?: Record<string, string>;
}
export interface CrushConfig {
    providers?: Record<string, CrushProviderConfig>;
    mcp?: Record<string, CrushMCPServerConfig>;
    [key: string]: any;
}
export declare class CrushManager {
    private static instance;
    private configPath;
    private constructor();
    static getInstance(): CrushManager;
    /**
     * 确保配置目录存在
     */
    private ensureConfigDir;
    /**
     * 读取配置
     */
    getConfig(): CrushConfig;
    /**
     * 保存配置
     */
    saveConfig(config: CrushConfig): void;
    /**
     * 获取 base_url（根据套餐类型）
     */
    private getBaseUrl;
    /**
     * 加载 GLM Coding Plan 配置到 Crush
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
        config: CrushMCPServerConfig;
    }>;
    /**
     * 获取所有 MCP 服务器配置
     */
    getAllMCPServers(): Record<string, CrushMCPServerConfig>;
    /**
     * 检测当前 Crush 配置的套餐和 API Key
     */
    detectCurrentConfig(): {
        plan: 'glm_coding_plan_global' | 'glm_coding_plan_china' | null;
        apiKey: string | null;
    };
}
export declare const crushManager: CrushManager;
