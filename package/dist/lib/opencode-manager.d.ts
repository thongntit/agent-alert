import { MCPService } from './mcp-manager.js';
export interface OpenCodeConfig {
    $schema?: string;
    provider?: Record<string, {
        options?: {
            apiKey?: string;
            [key: string]: any;
        };
        [key: string]: any;
    }>;
    model?: string;
    small_model?: string;
    mcp?: Record<string, OpenCodeMCPServerConfig>;
    [key: string]: any;
}
export interface OpenCodeMCPServerConfig {
    type: 'local' | 'remote';
    command?: string[];
    environment?: Record<string, string>;
    url?: string;
    headers?: Record<string, string>;
}
export declare class OpenCodeManager {
    private static instance;
    private configPath;
    private constructor();
    static getInstance(): OpenCodeManager;
    /**
     * 确保配置目录存在
     */
    private ensureConfigDir;
    /**
     * 读取配置
     */
    getConfig(): OpenCodeConfig;
    /**
     * 保存配置
     */
    saveConfig(config: OpenCodeConfig): void;
    /**
     * 获取 provider 名称（根据套餐类型）
     */
    private getProviderName;
    /**
     * 加载 GLM Coding Plan 配置到 OpenCode
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
        config: OpenCodeMCPServerConfig;
    }>;
    /**
     * 获取所有 MCP 服务器配置
     */
    getAllMCPServers(): Record<string, OpenCodeMCPServerConfig>;
    /**
     * 检测当前 OpenCode 配置的套餐和 API Key
     */
    detectCurrentConfig(): {
        plan: 'glm_coding_plan_global' | 'glm_coding_plan_china' | null;
        apiKey: string | null;
    };
}
export declare const openCodeManager: OpenCodeManager;
