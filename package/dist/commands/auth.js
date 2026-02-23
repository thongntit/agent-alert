import inquirer from 'inquirer';
import terminalLink from 'terminal-link';
import ora from 'ora';
import { configManager } from '../lib/config.js';
import { i18n } from '../lib/i18n.js';
import chalk from 'chalk';
import { claudeCodeManager } from '../lib/claude-code-manager.js';
import { openCodeManager } from '../lib/opencode-manager.js';
import { crushManager } from '../lib/crush-manager.js';
import { factoryDroidManager } from '../lib/factory-droid-manager.js';
import { validateApiKey } from '../lib/api-validator.js';
/**
 * 支持的工具列表
 */
const SUPPORTED_RELOAD_TOOLS = ['claude', 'claude-code', 'opencode', 'crush', 'factory-droid'];
/**
 * 重新加载配置到指定工具
 */
async function reloadToTool(tool) {
    const normalizedTool = tool.toLowerCase();
    if (!SUPPORTED_RELOAD_TOOLS.includes(normalizedTool)) {
        console.log(chalk.red(i18n.t('auth.reload_tool_not_supported', { tool })));
        return;
    }
    const plan = configManager.getPlan();
    const apiKey = configManager.getApiKey();
    if (!plan || !apiKey) {
        console.log(chalk.red(i18n.t('auth.reload_missing_config')));
        return;
    }
    // 确定工具名称
    const toolDisplayName = normalizedTool === 'opencode' ? 'OpenCode'
        : normalizedTool === 'crush' ? 'Crush'
            : normalizedTool === 'factory-droid' ? 'Factory Droid'
                : 'Claude Code';
    console.log(chalk.blue(i18n.t('auth.reloading', { tool: toolDisplayName })));
    try {
        if (normalizedTool === 'opencode') {
            openCodeManager.loadGLMConfig(plan, apiKey);
        }
        else if (normalizedTool === 'crush') {
            crushManager.loadGLMConfig(plan, apiKey);
        }
        else if (normalizedTool === 'factory-droid') {
            factoryDroidManager.loadGLMConfig(plan, apiKey);
        }
        else {
            claudeCodeManager.loadGLMConfig(plan, apiKey);
        }
        await new Promise(resolve => setTimeout(resolve, 800));
        console.log(chalk.green(i18n.t('auth.reloaded', { tool: toolDisplayName })));
    }
    catch (error) {
        console.log(chalk.red(i18n.t('auth.reload_failed')));
        if (error instanceof Error) {
            console.log(chalk.red(error.message));
        }
    }
}
/**
 * 撤销 API Key
 */
async function revokeApiKey() {
    const { confirm } = await inquirer.prompt([
        {
            type: 'confirm',
            name: 'confirm',
            message: i18n.t('auth.revoke_confirm'),
            default: false
        }
    ]);
    if (confirm) {
        configManager.revokeApiKey();
        console.log(chalk.green(i18n.t('auth.revoked')));
    }
    else {
        console.log(chalk.yellow(i18n.t('auth.not_revoked')));
    }
}
/**
 * 交互式设置 API Key
 */
async function interactiveAuth() {
    const { service } = await inquirer.prompt([
        {
            type: 'list',
            name: 'service',
            message: i18n.t('auth.service_prompt'),
            choices: [
                { name: i18n.t('wizard.plan_global'), value: 'glm_coding_plan_global' },
                { name: i18n.t('wizard.plan_china'), value: 'glm_coding_plan_china' }
            ]
        }
    ]);
    const apiKeyUrl = service === 'glm_coding_plan_global'
        ? 'https://z.ai/manage-apikey/apikey-list'
        : 'https://bigmodel.cn/usercenter/proj-mgmt/apikeys';
    const clickableUrl = terminalLink(apiKeyUrl, apiKeyUrl, { fallback: () => apiKeyUrl });
    console.log(chalk.blue('\n💡 ' + i18n.t('auth.get_api_key_hint', { url: clickableUrl }) + '\n'));
    const { token } = await inquirer.prompt([
        {
            type: 'password',
            name: 'token',
            message: i18n.t('auth.token_prompt'),
            validate: (input) => {
                if (!input || input.trim().length === 0) {
                    return i18n.t('auth.token_required');
                }
                return true;
            }
        }
    ]);
    // Validate API Key
    const spinner = ora({
        text: i18n.t('wizard.validating_api_key'),
        spinner: 'dots'
    }).start();
    const validationResult = await validateApiKey(token.trim(), service);
    if (!validationResult.valid) {
        if (validationResult.error === 'invalid_api_key') {
            spinner.fail(chalk.red(i18n.t('wizard.api_key_invalid')));
        }
        else {
            spinner.fail(chalk.red(i18n.t('wizard.api_key_network_error')));
        }
        return;
    }
    spinner.succeed(chalk.green(i18n.t('wizard.api_key_valid')));
    configManager.setPlan(service);
    configManager.setApiKey(token.trim());
    console.log(chalk.green(i18n.t('auth.saved')));
}
/**
 * 直接设置 API Key
 */
async function directAuth(service, token) {
    if (service !== 'glm_coding_plan_global' && service !== 'glm_coding_plan_china') {
        console.log(chalk.red(i18n.t('auth.service_not_supported', { service })));
        return;
    }
    const spinner = ora({
        text: i18n.t('wizard.validating_api_key'),
        spinner: 'star2'
    }).start();
    const validationResult = await validateApiKey(token, service);
    await new Promise(resolve => setTimeout(resolve, 800));
    if (!validationResult.valid) {
        if (validationResult.error === 'invalid_api_key') {
            spinner.fail(chalk.red(i18n.t('wizard.api_key_invalid')));
        }
        else {
            spinner.fail(chalk.red(i18n.t('wizard.api_key_network_error')));
        }
    }
    else {
        configManager.setPlan(service);
        configManager.setApiKey(token);
        spinner.succeed(chalk.green(i18n.t('auth.saved')));
    }
}
export async function authCommand(args) {
    // 无参数：交互式模式
    if (args.length === 0) {
        await interactiveAuth();
        return;
    }
    // chelper auth revoke
    if (args[0] === 'revoke') {
        await revokeApiKey();
        return;
    }
    // chelper auth reload <tool>
    if (args[0] === 'reload') {
        await reloadToTool(args[1] || '');
        return;
    }
    // chelper auth <service> <token>
    if (args.length >= 2) {
        await directAuth(args[0], args[1]);
        return;
    }
    // 显示用法
    console.log(i18n.t('auth.set_usage'));
}
