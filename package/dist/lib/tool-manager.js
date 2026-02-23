import { execSync } from 'child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { claudeCodeManager } from './claude-code-manager.js';
import { openCodeManager } from './opencode-manager.js';
import { crushManager } from './crush-manager.js';
import { factoryDroidManager } from './factory-droid-manager.js';
import { i18n } from './i18n.js';
import inquirer from 'inquirer';
import chalk from 'chalk';
import terminalLink from 'terminal-link';
import ora from "ora";
import { logger } from '../utils/logger.js';
export const SUPPORTED_TOOLS = {
    'claude-code': {
        name: 'claude-code',
        command: 'claude',
        installCommand: 'npm install -g @anthropic-ai/claude-code',
        configPath: join(homedir(), '.claude', 'settings.json'),
        displayName: 'Claude Code'
    },
    'opencode': {
        name: 'opencode',
        command: 'opencode',
        installCommand: 'npm install -g opencode-ai',
        configPath: join(homedir(), '.config', 'opencode', 'opencode.json'),
        displayName: 'OpenCode'
    },
    'crush': {
        name: 'crush',
        command: 'crush',
        installCommand: 'npm install -g @charmland/crush',
        configPath: join(homedir(), '.config', 'crush', 'crush.json'),
        displayName: 'Crush'
    },
    'factory-droid': {
        name: 'factory-droid',
        command: 'droid',
        installCommand: process.platform === 'win32'
            ? 'irm https://app.factory.ai/cli/windows | iex'
            : 'curl -fsSL https://app.factory.ai/cli | sh',
        configPath: join(homedir(), '.factory', 'config.json'),
        displayName: 'Factory Droid'
    }
};
export class ToolManager {
    static instance;
    constructor() { }
    static getInstance() {
        if (!ToolManager.instance) {
            ToolManager.instance = new ToolManager();
        }
        return ToolManager.instance;
    }
    isToolInstalled(toolName) {
        const tool = SUPPORTED_TOOLS[toolName];
        if (!tool)
            return false;
        try {
            // Windows 使用 where 命令，Unix 系统使用 which 命令
            const checkCommand = process.platform === 'win32'
                ? `where ${tool.command}`
                : `which ${tool.command}`;
            execSync(checkCommand, { stdio: 'pipe' });
            return true;
        }
        catch {
            return false;
        }
    }
    async installTool(toolName) {
        const tool = SUPPORTED_TOOLS[toolName];
        if (!tool) {
            throw new Error(`Unknown tool: ${toolName}`);
        }
        const spinner = ora(i18n.t('wizard.installing_tool')).start();
        try {
            // 首次尝试正常安装
            spinner.info(chalk.gray('$ ') + chalk.white(tool.installCommand));
            spinner.stop();
            execSync(tool.installCommand, { stdio: 'inherit' });
            if (toolName === 'factory-droid') {
                spinner.info(chalk.yellow(`\n⚠️  ${i18n.t('install.manual_action_detected')}`));
                const { confirmed } = await inquirer.prompt([
                    {
                        type: 'confirm',
                        name: 'confirmed',
                        message: i18n.t('install.confirm_manual_action_done'),
                        default: false
                    }
                ]);
                if (!confirmed) {
                    console.log(chalk.gray(`\n📌 ${i18n.t('install.complete_manual_action_hint')}`));
                    throw new Error(i18n.t('install.user_cancelled'));
                }
            }
            spinner.succeed(i18n.t('wizard.tool_installed'));
        }
        catch (error) {
            spinner.fail(i18n.t('wizard.install_failed'));
            if (toolName === 'factory-droid' && process.platform === 'win32') {
                spinner.info(chalk.yellow(`\n⚠️  ${i18n.t('install.factory_irm_install_tip')}\n`));
            }
            // 检查是否是权限错误 (EACCES)
            // execSync 的错误信息可能在 stderr 中，需要检查多个来源
            const errorMessage = (error.message || '') + (error.stderr?.toString() || '') + (error.stdout?.toString() || '');
            const isPermissionError = errorMessage.includes('EACCES') ||
                errorMessage.includes('permission denied') ||
                errorMessage.includes('EPERM') ||
                error.status === 243; // npm 权限错误的退出码
            if (!isPermissionError) {
                // 如果不是权限错误，直接抛出
                throw new Error(`Failed to install ${tool.displayName}: ${error}`);
            }
            console.log('\n⚠️  ' + i18n.t('install.permission_detected') + '\n');
            // Windows 平台处理
            if (process.platform === 'win32') {
                try {
                    // Windows: 尝试使用用户级安装（不需要管理员权限）
                    const userInstallCommand = tool.installCommand.replace('npm install -g', 'npm install -g --force');
                    console.log('🔧 ' + i18n.t('install.trying_solution', { num: '1', desc: i18n.t('install.using_force') }));
                    console.log(chalk.gray('$ ') + chalk.white(userInstallCommand));
                    execSync(userInstallCommand, { stdio: 'inherit' });
                    console.log('\n✅ ' + i18n.t('install.permission_fixed'));
                    return;
                }
                catch (retryError) {
                    // 如果还是失败，显示解决方案并询问用户
                    console.log(`Retry install error ${retryError}`);
                    console.log('\n❌ ' + i18n.t('install.auto_fix_failed'));
                    console.log(chalk.yellow('\n📌 ' + i18n.t('install.windows_solutions')));
                    console.log('');
                    // 方案 1: 以管理员身份运行
                    console.log(chalk.cyan.bold(i18n.t('install.windows_solution_1_title')));
                    console.log(chalk.gray('  ' + i18n.t('install.windows_solution_1_step1')));
                    console.log(chalk.gray('  ' + i18n.t('install.windows_solution_1_step2')));
                    console.log(chalk.gray('  ' + i18n.t('install.windows_solution_1_step3')));
                    console.log(chalk.white(`  ${tool.installCommand}`));
                    console.log('');
                    // 方案 2: 用户级安装
                    console.log(chalk.cyan.bold(i18n.t('install.windows_solution_2_title')));
                    console.log(chalk.gray('  ' + i18n.t('install.windows_solution_2_command')));
                    console.log(chalk.white(`  ${tool.installCommand.replace('npm install -g', 'npm install -g --prefix=%APPDATA%\\npm')}`));
                    console.log('');
                    // 询问用户是否已完成安装
                    const { action } = await inquirer.prompt([
                        {
                            type: 'list',
                            name: 'action',
                            message: i18n.t('install.what_next'),
                            choices: [
                                { name: i18n.t('install.installed_continue'), value: 'continue' },
                                { name: i18n.t('install.cancel_install'), value: 'cancel' }
                            ]
                        }
                    ]);
                    if (action === 'cancel') {
                        throw new Error(i18n.t('install.user_cancelled'));
                    }
                    // 验证是否真的安装成功
                    if (!this.isToolInstalled(toolName)) {
                        console.log(chalk.red('\n❌ ' + i18n.t('install.still_not_installed', { tool: tool.displayName })));
                        throw new Error(`${tool.displayName} is not installed`);
                    }
                    console.log(chalk.green('\n✅ ' + i18n.t('install.verified_success', { tool: tool.displayName })));
                    return;
                }
            }
            // macOS 和 Linux 平台处理 - 显示建议而不是自动执行
            console.log(chalk.yellow('\n📌 ' + i18n.t('install.unix_solutions')));
            console.log('');
            // 方案 1: 使用 sudo
            console.log(chalk.cyan.bold(i18n.t('install.unix_solution_1_title')));
            console.log(chalk.gray('  ' + i18n.t('install.unix_solution_1_desc')));
            console.log(chalk.white(`  sudo ${tool.installCommand}`));
            console.log('');
            // 方案 2: 使用 nvm (推荐)
            const npmDocsUrl = 'https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally';
            const clickableLink = terminalLink(npmDocsUrl, npmDocsUrl, { fallback: () => npmDocsUrl });
            console.log(chalk.cyan.bold(i18n.t('install.unix_solution_2_title')));
            console.log(chalk.gray('  ' + i18n.t('install.unix_solution_2_desc')));
            console.log(chalk.blue('  📖 ' + i18n.t('install.npm_docs_link') + ': ') + clickableLink);
            console.log('');
            // 询问用户是否已完成安装
            const { action } = await inquirer.prompt([
                {
                    type: 'list',
                    name: 'action',
                    message: i18n.t('install.what_next'),
                    choices: [
                        { name: i18n.t('install.installed_continue'), value: 'continue' },
                        { name: i18n.t('install.cancel_install'), value: 'cancel' }
                    ]
                }
            ]);
            if (action === 'cancel') {
                throw new Error(i18n.t('install.user_cancelled'));
            }
            // 验证是否真的安装成功
            if (!this.isToolInstalled(toolName)) {
                console.log(chalk.red('\n❌ ' + i18n.t('install.still_not_installed', { tool: tool.displayName })));
                throw new Error(`${tool.displayName} is not installed`);
            }
            console.log(chalk.green('\n✅ ' + i18n.t('install.verified_success', { tool: tool.displayName })));
            return;
        }
    }
    getToolConfig(toolName) {
        const tool = SUPPORTED_TOOLS[toolName];
        if (!tool) {
            throw new Error(`Unknown tool: ${toolName}`);
        }
        // Claude Code 使用专门的管理器
        if (toolName === 'claude-code') {
            return {
                settings: claudeCodeManager.getSettings(),
                mcp: claudeCodeManager.getMCPConfig()
            };
        }
        // OpenCode 使用专门的管理器
        if (toolName === 'opencode') {
            return openCodeManager.getConfig();
        }
        // Crush 使用专门的管理器
        if (toolName === 'crush') {
            return crushManager.getConfig();
        }
        // Factory Droid 使用专门的管理器
        if (toolName === 'factory-droid') {
            return factoryDroidManager.getConfig();
        }
        try {
            if (existsSync(tool.configPath)) {
                const content = readFileSync(tool.configPath, 'utf-8');
                return JSON.parse(content);
            }
        }
        catch (error) {
            console.warn(`Failed to read config for ${toolName}:`, error);
            logger.logError(`ToolManager.getToolConfig(${toolName})`, error);
        }
        return null;
    }
    updateToolConfig(toolName, config) {
        const tool = SUPPORTED_TOOLS[toolName];
        if (!tool) {
            throw new Error(`Unknown tool: ${toolName}`);
        }
        // Claude Code 使用专门的管理器
        if (toolName === 'claude-code') {
            if (config.settings) {
                claudeCodeManager.saveSettings(config.settings);
            }
            if (config.mcp) {
                claudeCodeManager.saveMCPConfig(config.mcp);
            }
            return;
        }
        // OpenCode 使用专门的管理器
        if (toolName === 'opencode') {
            openCodeManager.saveConfig(config);
            return;
        }
        // Crush 使用专门的管理器
        if (toolName === 'crush') {
            crushManager.saveConfig(config);
            return;
        }
        // Factory Droid 使用专门的管理器
        if (toolName === 'factory-droid') {
            factoryDroidManager.saveConfig(config);
            return;
        }
        try {
            // 使用 dirname 获取目录路径，确保跨平台兼容（Windows/macOS/Linux）
            const configDir = dirname(tool.configPath);
            if (!existsSync(configDir)) {
                mkdirSync(configDir, { recursive: true });
            }
            writeFileSync(tool.configPath, JSON.stringify(config, null, 2), 'utf-8');
        }
        catch (error) {
            throw new Error(`Failed to update config for ${toolName}: ${error}`);
        }
    }
    loadGLMConfig(toolName, plan, apiKey) {
        const tool = SUPPORTED_TOOLS[toolName];
        if (!tool) {
            throw new Error(`Unknown tool: ${toolName}`);
        }
        // Claude Code 使用专门的管理器
        if (toolName === 'claude-code') {
            claudeCodeManager.loadGLMConfig(plan, apiKey);
            return;
        }
        // OpenCode 使用专门的管理器
        if (toolName === 'opencode') {
            openCodeManager.loadGLMConfig(plan, apiKey);
            return;
        }
        // Crush 使用专门的管理器
        if (toolName === 'crush') {
            crushManager.loadGLMConfig(plan, apiKey);
            return;
        }
        // Factory Droid 使用专门的管理器
        if (toolName === 'factory-droid') {
            factoryDroidManager.loadGLMConfig(plan, apiKey);
            return;
        }
        const baseUrl = plan === 'glm_coding_plan_global'
            ? 'https://api.z.ai/api/coding/paas/v4'
            : 'https://open.bigmodel.cn/api/coding/paas/v4';
        let config = this.getToolConfig(toolName) || {};
        // Update with GLM Coding Plan configuration
        config = {
            ...config,
            apiKey: apiKey,
            baseUrl: baseUrl,
            model: 'glm-4-plus',
            provider: 'glm-coding-plan',
            plan: plan
        };
        this.updateToolConfig(toolName, config);
    }
    getInstalledTools() {
        return Object.keys(SUPPORTED_TOOLS).filter(toolName => this.isToolInstalled(toolName));
    }
    getSupportedTools() {
        return Object.values(SUPPORTED_TOOLS).filter(tool => !tool.hidden);
    }
    isGitInstalled() {
        try {
            // Windows 使用 where 命令，Unix 系统使用 which 命令
            const checkCommand = process.platform === 'win32'
                ? `where git`
                : `which git`;
            execSync(checkCommand, { stdio: 'pipe' });
            return true;
        }
        catch {
            return false;
        }
    }
}
export const toolManager = ToolManager.getInstance();
