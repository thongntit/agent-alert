import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { logger } from '../utils/logger.js';
export class ClaudeCodeManager {
    static instance;
    settingsPath;
    mcpConfigPath;
    constructor() {
        // Claude Code 配置文件路径（跨平台支持）
        // - macOS/Linux: ~/.claude/settings.json 和 ~/.claude.json
        // - Windows: %USERPROFILE%\.claude\settings.json 和 %USERPROFILE%\.claude.json
        //   (例如: C:\Users\username\.claude\settings.json)
        this.settingsPath = join(homedir(), '.claude', 'settings.json');
        this.mcpConfigPath = join(homedir(), '.claude.json');
    }
    static getInstance() {
        if (!ClaudeCodeManager.instance) {
            ClaudeCodeManager.instance = new ClaudeCodeManager();
        }
        return ClaudeCodeManager.instance;
    }
    /**
     * 确保配置目录存在
     */
    ensureConfigDir(filePath) {
        const dir = dirname(filePath);
        if (!existsSync(dir)) {
            mkdirSync(dir, { recursive: true });
        }
    }
    /**
     * 读取 settings.json 配置
     */
    getSettings() {
        try {
            if (existsSync(this.settingsPath)) {
                const content = readFileSync(this.settingsPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn('Failed to read Claude Code settings:', error);
            logger.logError('ClaudeCodeManager.getSettings', error);
        }
        return {};
    }
    /**
     * 保存 settings.json 配置
     */
    saveSettings(config) {
        try {
            this.ensureConfigDir(this.settingsPath);
            writeFileSync(this.settingsPath, JSON.stringify(config, null, 2), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to save Claude Code settings: ${error}`);
        }
    }
    /**
     * 读取 MCP 配置 (~/.claude.json)
     */
    getMCPConfig() {
        try {
            if (existsSync(this.mcpConfigPath)) {
                const content = readFileSync(this.mcpConfigPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn('Failed to read Claude Code MCP config:', error);
            logger.logError('ClaudeCodeManager.getMCPConfig', error);
        }
        return {};
    }
    /**
     * 保存 MCP 配置 (~/.claude.json)
     */
    saveMCPConfig(config) {
        try {
            this.ensureConfigDir(this.mcpConfigPath);
            writeFileSync(this.mcpConfigPath, JSON.stringify(config, null, 2), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to save Claude Code MCP config: ${error}`);
        }
    }
    /**
     * 加载 GLM Coding Plan 配置到 Claude Code
     */
    loadGLMConfig(plan, apiKey) {
        // 1. 确保 .claude.json 中有 hasCompletedOnboarding: true
        this.ensureOnboardingCompleted();
        // 2. 清理 shell rc 文件中的 ANTHROPIC_API_KEY 和 ANTHROPIC_BASE_URL
        this.cleanupShellEnvVars();
        // 3. 加载配置到 settings.json
        const currentSettings = this.getSettings();
        // 从 env 中移除 ANTHROPIC_API_KEY（如果存在），统一使用 ANTHROPIC_AUTH_TOKEN
        const currentEnv = currentSettings.env || {};
        const { ANTHROPIC_API_KEY: _, ...cleanedEnv } = currentEnv;
        const glmConfig = {
            ...currentSettings,
            env: {
                ...cleanedEnv,
                ANTHROPIC_AUTH_TOKEN: apiKey,
                ANTHROPIC_BASE_URL: plan == "glm_coding_plan_global" ? 'https://api.z.ai/api/anthropic' : 'https://open.bigmodel.cn/api/anthropic',
                API_TIMEOUT_MS: '3000000',
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: 1
            }
        };
        this.saveSettings(glmConfig);
    }
    /**
     * 确保 .claude.json 中有 hasCompletedOnboarding: true
     */
    ensureOnboardingCompleted() {
        try {
            const mcpConfig = this.getMCPConfig();
            if (!mcpConfig.hasCompletedOnboarding) {
                this.saveMCPConfig({ ...mcpConfig, hasCompletedOnboarding: true });
            }
        }
        catch (error) {
            console.warn('Failed to ensure onboarding completed:', error);
            logger.logError('ClaudeCodeManager.ensureOnboardingCompleted', error);
        }
    }
    /**
     * 清理 shell rc 文件中的 ANTHROPIC_API_KEY 和 ANTHROPIC_BASE_URL 环境变量
     */
    cleanupShellEnvVars() {
        // 检查当前环境变量是否有这些值
        if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_BASE_URL) {
            return;
        }
        try {
            // 根据操作系统和 shell 类型确定 rc 文件路径
            const rcFile = this.getShellRcFilePath();
            if (!rcFile || !existsSync(rcFile)) {
                return;
            }
            let content = readFileSync(rcFile, 'utf-8');
            const originalContent = content;
            // 移除 ANTHROPIC_BASE_URL 和 ANTHROPIC_API_KEY 相关行
            const linesToRemove = [
                /^\s*export\s+ANTHROPIC_BASE_URL=.*$/gm,
                /^\s*export\s+ANTHROPIC_API_KEY=.*$/gm,
                /^\s*#\s*Claude Code environment variables\s*$/gm
            ];
            for (const pattern of linesToRemove) {
                content = content.replace(pattern, '');
            }
            // 如果内容有变化，写回文件
            if (content !== originalContent) {
                writeFileSync(rcFile, content, 'utf-8');
                console.log(`Cleaned up ANTHROPIC_* environment variables from ${rcFile}`);
                setTimeout(() => { }, 1000);
            }
        }
        catch (error) {
            console.warn('Failed to cleanup shell environment variables:', error);
            logger.logError('ClaudeCodeManager.cleanupShellEnvVars', error);
            setTimeout(() => { }, 1000);
        }
    }
    /**
     * 获取当前 shell 的 rc 文件路径
     */
    getShellRcFilePath() {
        const home = homedir();
        // Windows 不使用 rc 文件
        if (process.platform === 'win32') {
            return null;
        }
        // 获取当前 shell
        const shell = process.env.SHELL || '';
        const shellName = shell.split('/').pop() || '';
        switch (shellName) {
            case 'bash':
                return join(home, '.bashrc');
            case 'zsh':
                return join(home, '.zshrc');
            case 'fish':
                return join(home, '.config', 'fish', 'config.fish');
            default:
                return join(home, '.profile');
        }
    }
    /**
     * 卸载 GLM Coding Plan 配置从 Claude Code
     */
    unloadGLMConfig() {
        const currentSettings = this.getSettings();
        if (!currentSettings.env) {
            return;
        }
        // 删除 GLM Coding Plan 相关的环境变量
        const { ANTHROPIC_AUTH_TOKEN: _1, ANTHROPIC_BASE_URL: _2, API_TIMEOUT_MS: _3, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: _4, ...otherEnv } = currentSettings.env;
        const newSettings = {
            ...currentSettings,
            env: otherEnv
        };
        // 如果 env 为空对象，则删除 env 字段
        if (newSettings.env && Object.keys(newSettings.env).length === 0) {
            delete newSettings.env;
        }
        this.saveSettings(newSettings);
    }
    /**
     * 检查 MCP 服务是否已安装
     */
    isMCPInstalled(mcpId) {
        try {
            const config = this.getMCPConfig();
            if (!config.mcpServers) {
                return false;
            }
            return mcpId in config.mcpServers;
        }
        catch {
            return false;
        }
    }
    /**
     * 安装 MCP 服务
     * @param mcp MCP 服务定义
     * @param apiKey API 密钥
     * @param plan 套餐类型 (glm_coding_plan_global 或 glm_coding_plan_china)
     */
    installMCP(mcp, apiKey, plan) {
        try {
            const config = this.getMCPConfig();
            if (!config.mcpServers) {
                config.mcpServers = {};
            }
            let mcpConfig;
            if (mcp.protocol === 'stdio') {
                // 确定环境变量
                let env = {};
                // 如果有 envTemplate，根据 plan 选择环境变量
                if (mcp.envTemplate && plan) {
                    env = { ...(mcp.envTemplate[plan] || {}) };
                }
                else if (mcp.env) {
                    // 使用固定的环境变量
                    env = { ...mcp.env };
                }
                // 如果需要认证，添加 API Key
                if (mcp.requiresAuth && apiKey) {
                    env.Z_AI_API_KEY = apiKey;
                }
                // stdio 类型的 MCP 配置
                mcpConfig = {
                    type: 'stdio',
                    command: mcp.command || 'npx',
                    args: mcp.args || [],
                    env
                };
            }
            else if (mcp.protocol === 'sse' || mcp.protocol === 'streamable-http') {
                // sse 和 streamable-http 类型的 MCP 配置
                // 根据 plan 确定 URL
                let url = '';
                if (mcp.urlTemplate && plan) {
                    // 使用 urlTemplate 根据 plan 选择 URL
                    url = mcp.urlTemplate[plan];
                }
                else if (mcp.url) {
                    // 使用固定 URL
                    url = mcp.url;
                }
                else {
                    throw new Error(`MCP ${mcp.id} missing url or urlTemplate`);
                }
                mcpConfig = {
                    type: mcp.protocol == 'sse' ? 'sse' : 'http',
                    url: url,
                    headers: {
                        ...(mcp.headers || {})
                    }
                };
                // 如果需要认证，添加 API Key 到 headers
                if (mcp.requiresAuth && apiKey) {
                    mcpConfig.headers = {
                        ...mcpConfig.headers,
                        'Authorization': `Bearer ${apiKey}`
                    };
                }
            }
            else {
                throw new Error(`Unsupported protocol: ${mcp.protocol}`);
            }
            config.mcpServers[mcp.id] = mcpConfig;
            this.saveMCPConfig(config);
        }
        catch (error) {
            throw new Error(`Failed to install MCP ${mcp.name}: ${error}`);
        }
    }
    /**
     * 卸载 MCP 服务
     */
    uninstallMCP(mcpId) {
        try {
            const config = this.getMCPConfig();
            if (!config.mcpServers) {
                return;
            }
            delete config.mcpServers[mcpId];
            this.saveMCPConfig(config);
        }
        catch (error) {
            throw new Error(`Failed to uninstall MCP ${mcpId}: ${error}`);
        }
    }
    /**
     * 获取已安装的 MCP 服务列表
     */
    getInstalledMCPs() {
        try {
            const config = this.getMCPConfig();
            if (!config.mcpServers) {
                return [];
            }
            return Object.keys(config.mcpServers);
        }
        catch {
            return [];
        }
    }
    /**
     * 获取所有 MCP 服务的安装状态
     */
    getMCPStatus(mcpServices) {
        const status = new Map();
        for (const mcp of mcpServices) {
            status.set(mcp.id, this.isMCPInstalled(mcp.id));
        }
        return status;
    }
    /**
     * 获取非内置的 MCP 服务列表
     * @param builtinIds 内置 MCP 服务的 ID 列表
     * @returns 其他 MCP 服务的详细信息
     */
    getOtherMCPs(builtinIds) {
        try {
            const config = this.getMCPConfig();
            if (!config.mcpServers) {
                return [];
            }
            const otherMCPs = [];
            for (const [id, mcpConfig] of Object.entries(config.mcpServers)) {
                if (!builtinIds.includes(id)) {
                    otherMCPs.push({ id, config: mcpConfig });
                }
            }
            return otherMCPs;
        }
        catch {
            return [];
        }
    }
    /**
     * 获取所有 MCP 服务器配置（包括内置和其他）
     */
    getAllMCPServers() {
        try {
            const config = this.getMCPConfig();
            return config.mcpServers || {};
        }
        catch {
            return {};
        }
    }
    /**
     * 检测当前 Claude Code 配置的套餐和 API Key
     * @returns 包含套餐类型和 API Key（部分隐藏）的对象
     */
    detectCurrentConfig() {
        try {
            const settings = this.getSettings();
            if (!settings.env || !settings.env.ANTHROPIC_AUTH_TOKEN) {
                return { plan: null, apiKey: null };
            }
            const apiKey = settings.env.ANTHROPIC_AUTH_TOKEN;
            const baseUrl = settings.env.ANTHROPIC_BASE_URL;
            let plan = null;
            if (baseUrl === 'https://api.z.ai/api/anthropic') {
                plan = 'glm_coding_plan_global';
            }
            else if (baseUrl === 'https://open.bigmodel.cn/api/anthropic') {
                plan = 'glm_coding_plan_china';
            }
            return { plan, apiKey };
        }
        catch {
            return { plan: null, apiKey: null };
        }
    }
}
export const claudeCodeManager = ClaudeCodeManager.getInstance();
