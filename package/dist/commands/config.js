import inquirer from 'inquirer';
import chalk from 'chalk';
import { wizard } from '../lib/wizard.js';
import { toolManager, SUPPORTED_TOOLS } from '../lib/tool-manager.js';
import { i18n } from '../lib/i18n.js';
export async function configCommand(args) {
    const subCommand = args[0];
    const toolName = args[1];
    // 如果没有参数，进入交互式选择
    if (!subCommand) {
        const { selectedTool } = await inquirer.prompt([
            {
                type: 'list',
                name: 'selectedTool',
                message: i18n.t('wizard.select_tool'),
                choices: Object.values(SUPPORTED_TOOLS).map(tool => ({
                    name: `${tool.displayName} (${tool.name})`,
                    value: tool.name
                }))
            }
        ]);
        // 检查工具是否安装
        if (!toolManager.isToolInstalled(selectedTool)) {
            console.log(chalk.yellow(`\n${i18n.t('wizard.tool_not_installed', { tool: SUPPORTED_TOOLS[selectedTool].displayName })}`));
            const { shouldInstall } = await inquirer.prompt([
                {
                    type: 'confirm',
                    name: 'shouldInstall',
                    message: i18n.t('wizard.install_tool_confirm'),
                    default: true
                }
            ]);
            if (shouldInstall) {
                try {
                    await toolManager.installTool(selectedTool);
                    await new Promise(resolve => setTimeout(resolve, 600));
                }
                catch (error) {
                    console.error(chalk.red(i18n.t('install.install_failed_detail')));
                    if (error.message) {
                        console.error(chalk.gray(error.message));
                    }
                    await new Promise(resolve => setTimeout(resolve, 600));
                    // 询问是否跳过安装
                    const { skipInstall } = await inquirer.prompt([
                        {
                            type: 'list',
                            name: 'skipInstall',
                            message: i18n.t('install.skip_install_confirm'),
                            choices: [
                                { name: i18n.t('install.skip_install_yes'), value: true },
                                { name: i18n.t('install.skip_install_no'), value: false }
                            ]
                        }
                    ]);
                    if (!skipInstall) {
                        return;
                    }
                }
            }
            else {
                console.log(chalk.yellow(i18n.t('wizard.install_skipped')));
                return;
            }
        }
        // 进入工具配置菜单
        await wizard.showToolMenu(selectedTool);
        return;
    }
    // 处理 claude-code 子命令
    if (subCommand === 'claude-code' || toolName === 'claude-code') {
        if (!toolManager.isToolInstalled('claude-code')) {
            console.log(chalk.yellow(i18n.t('wizard.tool_not_installed', { tool: 'Claude Code' })));
            const { shouldInstall } = await inquirer.prompt([
                {
                    type: 'confirm',
                    name: 'shouldInstall',
                    message: i18n.t('wizard.install_tool_confirm'),
                    default: true
                }
            ]);
            if (shouldInstall) {
                try {
                    await toolManager.installTool('claude-code');
                    await new Promise(resolve => setTimeout(resolve, 600));
                }
                catch (error) {
                    console.error(chalk.red(i18n.t('install.install_failed_detail')));
                    if (error.message) {
                        console.error(chalk.gray(error.message));
                    }
                    await new Promise(resolve => setTimeout(resolve, 600));
                    // 询问是否跳过安装
                    const { skipInstall } = await inquirer.prompt([
                        {
                            type: 'list',
                            name: 'skipInstall',
                            message: i18n.t('install.skip_install_confirm'),
                            choices: [
                                { name: i18n.t('install.skip_install_yes'), value: true },
                                { name: i18n.t('install.skip_install_no'), value: false }
                            ]
                        }
                    ]);
                    if (!skipInstall) {
                        return;
                    }
                }
            }
            else {
                console.log(chalk.yellow(i18n.t('wizard.install_skipped')));
                return;
            }
        }
        await wizard.showToolMenu('claude-code');
        return;
    }
    // 其他工具的支持
    if (SUPPORTED_TOOLS[subCommand]) {
        if (!toolManager.isToolInstalled(subCommand)) {
            console.log(chalk.yellow(i18n.t('wizard.tool_not_installed', { tool: SUPPORTED_TOOLS[subCommand].displayName })));
            return;
        }
        await wizard.showToolMenu(subCommand);
        return;
    }
    console.error(chalk.red(`Unknown command: ${subCommand}`));
    console.log(chalk.gray('Usage: chelper config [tool-name]'));
    console.log(chalk.gray('Available tools:'));
    Object.values(SUPPORTED_TOOLS).forEach(tool => {
        console.log(chalk.gray(`  - ${tool.name}: ${tool.displayName}`));
    });
}
