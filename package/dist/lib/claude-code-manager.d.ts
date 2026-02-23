import { MCPService } from './mcp-manager.js';
export interface ClaudeCodeSettingsConfig {
    env?: {
        ANTHROPIC_AUTH_TOKEN?: string;
        ANTHROPIC_BASE_URL?: string;
        API_TIMEOUT_MS?: string;
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC?: number;
        [key: string]: any;
    };
    [key: string]: any;
}
export interface ClaudeCodeMCPServerConfig {
    type: 'stdio' | 'sse' | 'http';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
    url?: string;
    headers?: Record<string, string>;
}
export interface ClaudeCodeMCPConfig {
    mcpServers?: Record<string, ClaudeCodeMCPServerConfig>;
    hasOpusPlanDefault?: boolean;
    lastReleaseNotesSeen?: string;
    hasCompletedOnboarding?: boolean;
    [key: string]: any;
}
export declare class ClaudeCodeManager {
    private static instance;
    private settingsPath;
    private mcpConfigPath;
    private constructor();
    static getInstance(): ClaudeCodeManager;
    /**
     * 确保配置目录存在
     */
    private ensureConfigDir;
    /**
     * 读取 settings.json 配置
     */
    getSettings(): ClaudeCodeSettingsConfig;
    /**
     * 保存 settings.json 配置
     */
    saveSettings(config: ClaudeCodeSettingsConfig): void;
    /**
     * 读取 MCP 配置 (~/.claude.json)
     */
    getMCPConfig(): ClaudeCodeMCPConfig;
    /**
     * 保存 MCP 配置 (~/.claude.json)
     */
    saveMCPConfig(config: ClaudeCodeMCPConfig): void;
    /**
     * 加载 GLM Coding Plan 配置到 Claude Code
     */
    loadGLMConfig(plan: 'glm_coding_plan_global' | 'glm_coding_plan_china', apiKey: string): void;
    /**
     * 确保 .claude.json 中有 hasCompletedOnboarding: true
     */
    private ensureOnboardingCompleted;
    /**
     * 清理 shell rc 文件中的 ANTHROPIC_API_KEY 和 ANTHROPIC_BASE_URL 环境变量
     */
    private cleanupShellEnvVars;
    /**
     * 获取当前 shell 的 rc 文件路径
     */
    private getShellRcFilePath;
    /**
     * 卸载 GLM Coding Plan 配置从 Claude Code
     */
    unloadGLMConfig(): void;
    /**
     * 检查 MCP 服务是否已安装
     */
    isMCPInstalled(mcpId: string): boolean;
    /**
     * 安装 MCP 服务
     * @param mcp MCP 服务定义
     * @param apiKey API 密钥
     * @param plan 套餐类型 (glm_coding_plan_global 或 glm_coding_plan_china)
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
     * @param builtinIds 内置 MCP 服务的 ID 列表
     * @returns 其他 MCP 服务的详细信息
     */
    getOtherMCPs(builtinIds: string[]): Array<{
        id: string;
        config: ClaudeCodeMCPServerConfig;
    }>;
    /**
     * 获取所有 MCP 服务器配置（包括内置和其他）
     */
    getAllMCPServers(): Record<string, ClaudeCodeMCPServerConfig>;
    /**
     * 检测当前 Claude Code 配置的套餐和 API Key
     * @returns 包含套餐类型和 API Key（部分隐藏）的对象
     */
    detectCurrentConfig(): {
        plan: 'glm_coding_plan_global' | 'glm_coding_plan_china' | null;
        apiKey: string | null;
    };
}
export declare const claudeCodeManager: ClaudeCodeManager;
