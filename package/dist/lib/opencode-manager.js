import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { logger } from '../utils/logger.js';
export class OpenCodeManager {
    static instance;
    configPath;
    constructor() {
        // OpenCode 配置文件路径
        // ~/.config/opencode/opencode.json
        this.configPath = join(homedir(), '.config', 'opencode', 'opencode.json');
    }
    static getInstance() {
        if (!OpenCodeManager.instance) {
            OpenCodeManager.instance = new OpenCodeManager();
        }
        return OpenCodeManager.instance;
    }
    /**
     * 确保配置目录存在
     */
    ensureConfigDir() {
        const dir = dirname(this.configPath);
        if (!existsSync(dir)) {
            mkdirSync(dir, { recursive: true });
        }
    }
    /**
     * 读取配置
     */
    getConfig() {
        try {
            if (existsSync(this.configPath)) {
                const content = readFileSync(this.configPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn('Failed to read OpenCode config:', error);
            logger.logError('OpenCodeManager.getConfig', error);
        }
        return {};
    }
    /**
     * 保存配置
     */
    saveConfig(config) {
        try {
            this.ensureConfigDir();
            writeFileSync(this.configPath, JSON.stringify(config, null, 4), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to save OpenCode config: ${error}`);
        }
    }
    /**
     * 获取 provider 名称（根据套餐类型）
     */
    getProviderName(plan) {
        return plan === 'glm_coding_plan_global' ? 'zai-coding-plan' : 'zhipuai-coding-plan';
    }
    /**
     * 加载 GLM Coding Plan 配置到 OpenCode
     */
    loadGLMConfig(plan, apiKey) {
        const currentConfig = this.getConfig();
        const providerName = this.getProviderName(plan);
        // 移除旧的 provider 配置（如果存在）
        const { provider: oldProvider, ...restConfig } = currentConfig;
        const newProvider = {};
        // 保留其他 provider（如果有的话），但移除旧的 coding-plan provider
        if (oldProvider) {
            for (const [key, value] of Object.entries(oldProvider)) {
                if (key !== 'zhipuai-coding-plan' && key !== 'zai-coding-plan') {
                    newProvider[key] = value;
                }
            }
        }
        // 添加新的 provider 配置
        newProvider[providerName] = {
            options: {
                apiKey: apiKey
            }
        };
        const newConfig = {
            $schema: 'https://opencode.ai/config.json',
            ...restConfig,
            provider: newProvider,
            model: `${providerName}/glm-4.6`,
            small_model: `${providerName}/glm-4.5-air`
        };
        this.saveConfig(newConfig);
    }
    /**
     * 卸载 GLM Coding Plan 配置
     */
    unloadGLMConfig() {
        const currentConfig = this.getConfig();
        // 移除 provider 中的 coding-plan 配置
        if (currentConfig.provider) {
            delete currentConfig.provider['zhipuai-coding-plan'];
            delete currentConfig.provider['zai-coding-plan'];
            // 如果 provider 为空，删除 provider 字段
            if (Object.keys(currentConfig.provider).length === 0) {
                delete currentConfig.provider;
            }
        }
        // 移除 model 和 small_model（如果是 coding-plan 的）
        if (currentConfig.model?.includes('coding-plan')) {
            delete currentConfig.model;
        }
        if (currentConfig.small_model?.includes('coding-plan')) {
            delete currentConfig.small_model;
        }
        this.saveConfig(currentConfig);
    }
    /**
     * 检查 MCP 服务是否已安装
     */
    isMCPInstalled(mcpId) {
        try {
            const config = this.getConfig();
            if (!config.mcp) {
                return false;
            }
            return mcpId in config.mcp;
        }
        catch {
            return false;
        }
    }
    /**
     * 安装 MCP 服务
     */
    installMCP(mcp, apiKey, plan) {
        try {
            const config = this.getConfig();
            if (!config.mcp) {
                config.mcp = {};
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
                    env = { ...mcp.env };
                }
                // 如果需要认证，添加 API Key
                if (mcp.requiresAuth && apiKey) {
                    env.Z_AI_API_KEY = apiKey;
                }
                // OpenCode 使用 local 类型和 command 数组
                const commandArray = [mcp.command || 'npx', ...(mcp.args || [])];
                mcpConfig = {
                    type: 'local',
                    command: commandArray,
                    environment: env
                };
            }
            else if (mcp.protocol === 'streamable-http') {
                // 根据 plan 确定 URL
                let url = '';
                if (mcp.urlTemplate && plan) {
                    url = mcp.urlTemplate[plan];
                }
                else if (mcp.url) {
                    url = mcp.url;
                }
                else {
                    throw new Error(`MCP ${mcp.id} missing url or urlTemplate`);
                }
                // OpenCode 使用 remote 或 http 类型
                mcpConfig = {
                    type: 'remote',
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
            config.mcp[mcp.id] = mcpConfig;
            this.saveConfig(config);
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
            const config = this.getConfig();
            if (!config.mcp) {
                return;
            }
            delete config.mcp[mcpId];
            this.saveConfig(config);
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
            const config = this.getConfig();
            if (!config.mcp) {
                return [];
            }
            return Object.keys(config.mcp);
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
     */
    getOtherMCPs(builtinIds) {
        try {
            const config = this.getConfig();
            if (!config.mcp) {
                return [];
            }
            const otherMCPs = [];
            for (const [id, mcpConfig] of Object.entries(config.mcp)) {
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
     * 获取所有 MCP 服务器配置
     */
    getAllMCPServers() {
        try {
            const config = this.getConfig();
            return config.mcp || {};
        }
        catch {
            return {};
        }
    }
    /**
     * 检测当前 OpenCode 配置的套餐和 API Key
     */
    detectCurrentConfig() {
        try {
            const config = this.getConfig();
            // 检查 provider 配置
            if (!config.provider) {
                return { plan: null, apiKey: null };
            }
            // 检查是否有 zai-coding-plan 或 zhipuai-coding-plan
            let plan = null;
            let apiKey = null;
            if (config.provider['zai-coding-plan']) {
                plan = 'glm_coding_plan_global';
                apiKey = config.provider['zai-coding-plan'].options?.apiKey || null;
            }
            else if (config.provider['zhipuai-coding-plan']) {
                plan = 'glm_coding_plan_china';
                apiKey = config.provider['zhipuai-coding-plan'].options?.apiKey || null;
            }
            return { plan, apiKey };
        }
        catch {
            return { plan: null, apiKey: null };
        }
    }
}
export const openCodeManager = OpenCodeManager.getInstance();
