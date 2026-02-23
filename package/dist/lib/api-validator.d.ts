/**
 * API Key 和网络验证模块
 * 通过调用模型列表 API 来验证 API Key 的有效性和网络连通性
 */
export interface ValidateApiKeyResult {
    valid: boolean;
    error?: 'network_error' | 'invalid_api_key' | 'unknown_error';
    message?: string;
}
/**
 * 验证 API Key 的有效性和网络连通性
 *
 * @param apiKey - API Key
 * @param plan - 套餐类型 (全球版或中国版)
 * @returns 验证结果，包含 valid 状态和可选的错误信息
 */
export declare function validateApiKey(apiKey: string, plan: 'glm_coding_plan_global' | 'glm_coding_plan_china'): Promise<ValidateApiKeyResult>;
