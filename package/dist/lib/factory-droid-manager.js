import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { logger } from '../utils/logger.js';
export class FactoryDroidManager {
    static instance;
    configPath;
    mcpConfigPath;
    constructor() {
        // Factory Droid 配置文件路径
        this.configPath = join(homedir(), '.factory', 'settings.json');
        // Factory Droid MCP 配置文件路径 (单独文件)
        this.mcpConfigPath = join(homedir(), '.factory', 'mcp.json');
    }
    static getInstance() {
        if (!FactoryDroidManager.instance) {
            FactoryDroidManager.instance = new FactoryDroidManager();
        }
        return FactoryDroidManager.instance;
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
     * 读取主配置
     */
    getConfig() {
        try {
            if (existsSync(this.configPath)) {
                const content = readFileSync(this.configPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn('Failed to read Factory Droid config:', error);
            logger.logError('FactoryDroidManager.getConfig', error);
        }
        return {};
    }
    /**
     * 保存主配置
     */
    saveConfig(config) {
        try {
            this.ensureConfigDir();
            writeFileSync(this.configPath, JSON.stringify(config, null, 2), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to save Factory Droid config: ${error}`);
        }
    }
    /**
     * 读取 MCP 配置
     */
    getMCPConfig() {
        try {
            if (existsSync(this.mcpConfigPath)) {
                const content = readFileSync(this.mcpConfigPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn('Failed to read Factory Droid MCP config:', error);
            logger.logError('FactoryDroidManager.getMCPConfig', error);
        }
        return {};
    }
    /**
     * 保存 MCP 配置
     */
    saveMCPConfig(config) {
        try {
            this.ensureConfigDir();
            writeFileSync(this.mcpConfigPath, JSON.stringify(config, null, 2), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to save Factory Droid MCP config: ${error}`);
        }
    }
    /**
     * 获取 baseUrl（根据套餐类型和协议）
     */
    getBaseUrl(plan, protocol) {
        if (protocol === 'anthropic') {
            return plan === 'glm_coding_plan_global'
                ? 'https://api.z.ai/api/anthropic'
                : 'https://open.bigmodel.cn/api/anthropic';
        }
        else {
            return plan === 'glm_coding_plan_global'
                ? 'https://api.z.ai/api/coding/paas/v4'
                : 'https://open.bigmodel.cn/api/coding/paas/v4';
        }
    }
    /**
     * 获取 displayName（根据套餐类型和协议）
     */
    getDisplayName(plan, protocol) {
        const planName = plan === 'glm_coding_plan_global' ? 'GLM Coding Plan Global' : 'GLM Coding Plan China';
        const protocolName = protocol === 'anthropic' ? 'Anthropic' : 'Openai';
        return `GLM-4.7 [${planName}] - ${protocolName}`;
    }
    /**
     * 加载 GLM Coding Plan 配置到 Factory Droid
     */
    loadGLMConfig(plan, apiKey) {
        const currentConfig = this.getConfig();
        // 创建 Anthropic 协议配置
        const anthropicModel = {
            displayName: this.getDisplayName(plan, 'anthropic'),
            model: 'glm-4.7',
            baseUrl: this.getBaseUrl(plan, 'anthropic'),
            apiKey,
            provider: 'anthropic',
            maxOutputTokens: 131072
        };
        // 创建 OpenAI Chat Completion 协议配置
        const openaiModel = {
            displayName: this.getDisplayName(plan, 'openai'),
            model: 'glm-4.7',
            baseUrl: this.getBaseUrl(plan, 'openai'),
            apiKey,
            provider: 'generic-chat-completion-api',
            maxOutputTokens: 131072
        };
        // 过滤掉旧的 GLM Coding Plan 配置（通过 displayName 判断）
        const existingModels = (currentConfig.customModels || []).filter(m => !m.displayName.includes('GLM Coding Plan'));
        const newConfig = {
            ...currentConfig,
            customModels: [...existingModels, anthropicModel, openaiModel]
        };
        this.saveConfig(newConfig);
    }
    /**
     * 卸载 GLM Coding Plan 配置
     */
    unloadGLMConfig() {
        const currentConfig = this.getConfig();
        // 过滤掉 GLM Coding Plan 配置
        if (currentConfig.customModels) {
            currentConfig.customModels = currentConfig.customModels.filter(m => !m.displayName.includes('GLM Coding Plan'));
            // 如果 customModels 为空，删除字段
            if (currentConfig.customModels.length === 0) {
                delete currentConfig.customModels;
            }
        }
        this.saveConfig(currentConfig);
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
                    env = { ...mcp.env };
                }
                // 如果需要认证，添加 API Key
                if (mcp.requiresAuth && apiKey) {
                    env.Z_AI_API_KEY = apiKey;
                }
                mcpConfig = {
                    type: 'stdio',
                    command: mcp.command || 'npx',
                    args: mcp.args || [],
                    env,
                    disabled: false
                };
            }
            else if (mcp.protocol === 'sse' || mcp.protocol === 'streamable-http') {
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
                // Factory Droid 使用 http 类型
                mcpConfig = {
                    type: 'http',
                    url: url,
                    headers: {
                        ...(mcp.headers || {})
                    },
                    disabled: false
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
     * 获取所有 MCP 服务器配置
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
     * 检测当前 Factory Droid 配置的套餐和 API Key
     */
    detectCurrentConfig() {
        try {
            const config = this.getConfig();
            // 查找 GLM Coding Plan 配置
            if (!config.customModels || config.customModels.length === 0) {
                return { plan: null, apiKey: null };
            }
            const glmModel = config.customModels.find(m => m.displayName.includes('GLM Coding Plan'));
            if (!glmModel) {
                return { plan: null, apiKey: null };
            }
            const apiKey = glmModel.apiKey || null;
            const baseUrl = glmModel.baseUrl;
            let plan = null;
            if (baseUrl === 'https://api.z.ai/api/coding/paas/v4' || baseUrl === 'https://api.z.ai/api/anthropic') {
                plan = 'glm_coding_plan_global';
            }
            else if (baseUrl === 'https://open.bigmodel.cn/api/coding/paas/v4' || baseUrl === 'https://open.bigmodel.cn/api/anthropic') {
                plan = 'glm_coding_plan_china';
            }
            return { plan, apiKey };
        }
        catch {
            return { plan: null, apiKey: null };
        }
    }
}
export const factoryDroidManager = FactoryDroidManager.getInstance();
