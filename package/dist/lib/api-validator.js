/**
 * API Key 和网络验证模块
 * 通过调用模型列表 API 来验证 API Key 的有效性和网络连通性
 */
import { logger } from '../utils/logger.js';
/**
 * 根据套餐类型获取验证 API 的 URL
 */
function getValidationUrl(plan) {
    return plan === 'glm_coding_plan_global'
        ? 'https://api.z.ai/api/coding/paas/v4/models'
        : 'https://open.bigmodel.cn/api/coding/paas/v4/models';
}
/**
 * 验证 API Key 的有效性和网络连通性
 *
 * @param apiKey - API Key
 * @param plan - 套餐类型 (全球版或中国版)
 * @returns 验证结果，包含 valid 状态和可选的错误信息
 */
export async function validateApiKey(apiKey, plan) {
    const url = getValidationUrl(plan);
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000); // 10 秒超时
        const response = await fetch(url, {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${apiKey}`,
                'Content-Type': 'application/json'
            },
            signal: controller.signal
        });
        clearTimeout(timeoutId);
        if (response.status === 401) {
            return {
                valid: false,
                error: 'invalid_api_key',
                message: 'API Key is invalid or expired'
            };
        }
        if (response.ok) {
            // 尝试解析响应以确保是有效的 JSON
            try {
                const data = await response.json();
                if (data && data.object === 'list') {
                    return { valid: true };
                }
            }
            catch {
                // JSON 解析失败但响应成功，仍然视为有效
                return { valid: true };
            }
            return { valid: true };
        }
        // 其他 HTTP 错误
        return {
            valid: false,
            error: 'unknown_error',
            message: `HTTP ${response.status}: ${response.statusText}`
        };
    }
    catch (error) {
        // 网络错误或超时
        logger.logError('validateApiKey', error);
        if (error instanceof Error) {
            if (error.name === 'AbortError') {
                return {
                    valid: false,
                    error: 'network_error',
                    message: 'Request timeout'
                };
            }
            return {
                valid: false,
                error: 'network_error',
                message: error.message
            };
        }
        return {
            valid: false,
            error: 'network_error',
            message: 'Network connection failed'
        };
    }
}
