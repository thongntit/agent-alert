import { toolManager } from './tool-manager.js';
import { claudeCodeManager } from './claude-code-manager.js';
import { openCodeManager } from './opencode-manager.js';
import { crushManager } from './crush-manager.js';
import { factoryDroidManager } from './factory-droid-manager.js';
// GLM Coding Plan预置的MCP服务
export const PRESET_MCP_SERVICES = [
    {
        id: 'zai-mcp-server',
        name: 'Vision MCP',
        type: 'builtin',
        protocol: 'stdio',
        requiresAuth: true,
        description: 'Vision MCP Local Server',
        command: 'npx',
        args: ['-y', '@z_ai/mcp-server'],
        envTemplate: {
            glm_coding_plan_global: {
                Z_AI_MODE: 'ZAI'
            },
            glm_coding_plan_china: {
                Z_AI_MODE: 'ZHIPU'
            }
        }
    },
    {
        id: 'web-search-prime',
        name: 'Web Search MCP',
        type: 'builtin',
        protocol: 'streamable-http',
        requiresAuth: true,
        description: 'Web Search Prime MCP Server',
        urlTemplate: {
            glm_coding_plan_global: 'https://api.z.ai/api/mcp/web_search_prime/mcp',
            glm_coding_plan_china: 'https://open.bigmodel.cn/api/mcp/web_search_prime/mcp'
        }
    },
    {
        id: 'web-reader',
        name: 'Web Reader MCP',
        type: 'builtin',
        protocol: 'streamable-http',
        requiresAuth: true,
        description: 'Web URL Reader MCP Server',
        urlTemplate: {
            glm_coding_plan_global: 'https://api.z.ai/api/mcp/web_reader/mcp',
            glm_coding_plan_china: 'https://open.bigmodel.cn/api/mcp/web_reader/mcp'
        }
    },
    {
        id: 'zread',
        name: 'ZRead MCP',
        type: 'builtin',
        protocol: 'streamable-http',
        requiresAuth: true,
        description: 'ZRead Github MCP Server',
        urlTemplate: {
            glm_coding_plan_global: 'https://api.z.ai/api/mcp/zread/mcp',
            glm_coding_plan_china: 'https://open.bigmodel.cn/api/mcp/zread/mcp'
        }
    }
];
export class MCPManager {
    static instance;
    constructor() { }
    static getInstance() {
        if (!MCPManager.instance) {
            MCPManager.instance = new MCPManager();
        }
        return MCPManager.instance;
    }
    getPresetServices() {
        return [...PRESET_MCP_SERVICES];
    }
    isMCPInstalled(toolName, mcpId) {
        try {
            // Claude Code 使用专门的管理器
            if (toolName === 'claude-code') {
                return claudeCodeManager.isMCPInstalled(mcpId);
            }
            // OpenCode 使用专门的管理器
            if (toolName === 'opencode') {
                return openCodeManager.isMCPInstalled(mcpId);
            }
            // Crush 使用专门的管理器
            if (toolName === 'crush') {
                return crushManager.isMCPInstalled(mcpId);
            }
            // Factory Droid 使用专门的管理器
            if (toolName === 'factory-droid') {
                return factoryDroidManager.isMCPInstalled(mcpId);
            }
            const config = toolManager.getToolConfig(toolName);
            if (!config || !config.mcpServers) {
                return false;
            }
            return mcpId in config.mcpServers;
        }
        catch {
            return false;
        }
    }
    installMCP(toolName, mcp, apiKey, plan) {
        try {
            // Claude Code 使用专门的管理器
            if (toolName === 'claude-code') {
                claudeCodeManager.installMCP(mcp, apiKey, plan);
                return;
            }
            // OpenCode 使用专门的管理器
            if (toolName === 'opencode') {
                openCodeManager.installMCP(mcp, apiKey, plan);
                return;
            }
            // Crush 使用专门的管理器
            if (toolName === 'crush') {
                crushManager.installMCP(mcp, apiKey, plan);
                return;
            }
            // Factory Droid 使用专门的管理器
            if (toolName === 'factory-droid') {
                factoryDroidManager.installMCP(mcp, apiKey, plan);
                return;
            }
            const config = toolManager.getToolConfig(toolName) || {};
            if (!config.mcpServers) {
                config.mcpServers = {};
            }
            // 根据协议类型配置不同的结构
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
                config.mcpServers[mcp.id] = {
                    type: 'stdio',
                    command: mcp.command,
                    args: mcp.args,
                    env
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
                    throw new Error(`MCP ${mcp.name} requires a URL but none was provided.`);
                }
                config.mcpServers[mcp.id] = {
                    type: mcp.protocol,
                    url: url,
                    headers: {
                        ...(mcp.headers || {}),
                        ...(apiKey && mcp.requiresAuth ? { 'Authorization': `Bearer ${apiKey}` } : {})
                    }
                };
            }
            toolManager.updateToolConfig(toolName, config);
        }
        catch (error) {
            throw new Error(`Failed to install MCP ${mcp.name}: ${error}`);
        }
    }
    uninstallMCP(toolName, mcpId) {
        try {
            // Claude Code 使用专门的管理器
            if (toolName === 'claude-code') {
                claudeCodeManager.uninstallMCP(mcpId);
                return;
            }
            // OpenCode 使用专门的管理器
            if (toolName === 'opencode') {
                openCodeManager.uninstallMCP(mcpId);
                return;
            }
            // Crush 使用专门的管理器
            if (toolName === 'crush') {
                crushManager.uninstallMCP(mcpId);
                return;
            }
            // Factory Droid 使用专门的管理器
            if (toolName === 'factory-droid') {
                factoryDroidManager.uninstallMCP(mcpId);
                return;
            }
            const config = toolManager.getToolConfig(toolName);
            if (!config || !config.mcpServers) {
                return;
            }
            delete config.mcpServers[mcpId];
            toolManager.updateToolConfig(toolName, config);
        }
        catch (error) {
            throw new Error(`Failed to uninstall MCP ${mcpId}: ${error}`);
        }
    }
    getInstalledMCPs(toolName) {
        try {
            // Claude Code 使用专门的管理器
            if (toolName === 'claude-code') {
                return claudeCodeManager.getInstalledMCPs();
            }
            // OpenCode 使用专门的管理器
            if (toolName === 'opencode') {
                return openCodeManager.getInstalledMCPs();
            }
            // Crush 使用专门的管理器
            if (toolName === 'crush') {
                return crushManager.getInstalledMCPs();
            }
            // Factory Droid 使用专门的管理器
            if (toolName === 'factory-droid') {
                return factoryDroidManager.getInstalledMCPs();
            }
            const config = toolManager.getToolConfig(toolName);
            if (!config || !config.mcpServers) {
                return [];
            }
            return Object.keys(config.mcpServers);
        }
        catch {
            return [];
        }
    }
    getMCPStatus(toolName) {
        // Claude Code 使用专门的管理器
        if (toolName === 'claude-code') {
            return claudeCodeManager.getMCPStatus(PRESET_MCP_SERVICES);
        }
        // OpenCode 使用专门的管理器
        if (toolName === 'opencode') {
            return openCodeManager.getMCPStatus(PRESET_MCP_SERVICES);
        }
        // Crush 使用专门的管理器
        if (toolName === 'crush') {
            return crushManager.getMCPStatus(PRESET_MCP_SERVICES);
        }
        // Factory Droid 使用专门的管理器
        if (toolName === 'factory-droid') {
            return factoryDroidManager.getMCPStatus(PRESET_MCP_SERVICES);
        }
        const status = new Map();
        for (const mcp of PRESET_MCP_SERVICES) {
            status.set(mcp.id, this.isMCPInstalled(toolName, mcp.id));
        }
        return status;
    }
}
export const mcpManager = MCPManager.getInstance();
