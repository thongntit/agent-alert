export interface MCPService {
    id: string;
    name: string;
    type: 'builtin' | 'custom';
    description: string;
    protocol: 'stdio' | 'sse' | 'streamable-http';
    requiresAuth: boolean;
    command?: string;
    args?: string[];
    env?: Record<string, string>;
    envTemplate?: {
        glm_coding_plan_global?: Record<string, string>;
        glm_coding_plan_china?: Record<string, string>;
    };
    url?: string;
    urlTemplate?: {
        glm_coding_plan_global: string;
        glm_coding_plan_china: string;
    };
    headers?: Record<string, string>;
}
export declare const PRESET_MCP_SERVICES: MCPService[];
export declare class MCPManager {
    private static instance;
    private constructor();
    static getInstance(): MCPManager;
    getPresetServices(): MCPService[];
    isMCPInstalled(toolName: string, mcpId: string): boolean;
    installMCP(toolName: string, mcp: MCPService, apiKey?: string, plan?: 'glm_coding_plan_global' | 'glm_coding_plan_china'): void;
    uninstallMCP(toolName: string, mcpId: string): void;
    getInstalledMCPs(toolName: string): string[];
    getMCPStatus(toolName: string): Map<string, boolean>;
}
export declare const mcpManager: MCPManager;
