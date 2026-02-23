import chalk from 'chalk';
import ora from 'ora';
import { configManager } from '../lib/config.js';
import { toolManager } from '../lib/tool-manager.js';
import { claudeCodeManager } from '../lib/claude-code-manager.js';
import { i18n } from '../lib/i18n.js';
import { validateApiKey } from '../lib/api-validator.js';
export async function doctorCommand() {
    const spinner = ora(i18n.t('doctor.checking')).start();
    const results = [];
    // Check 1: PATH environment variable
    spinner.text = i18n.t('doctor.check_path');
    try {
        const path = process.env.PATH || '';
        results.push({
            name: 'PATH',
            passed: path.length > 0,
            message: path.length > 0 ? undefined : 'PATH is empty'
        });
    }
    catch (error) {
        results.push({
            name: 'PATH',
            passed: false,
            message: String(error)
        });
    }
    await new Promise(resolve => setTimeout(resolve, 800));
    // Check 2: API Key & Network (combined check)
    spinner.text = i18n.t('doctor.check_api_key_network');
    const apiKey = configManager.getApiKey();
    const plan = configManager.getPlan();
    if (!apiKey || !plan) {
        results.push({
            name: 'API Key & Network',
            passed: false,
            message: chalk.yellow(i18n.t('doctor.api_key_missing'))
        });
    }
    else {
        const validationResult = await validateApiKey(apiKey, plan);
        if (validationResult.valid) {
            results.push({
                name: 'API Key & Network',
                passed: true
            });
        }
        else if (validationResult.error === 'invalid_api_key') {
            results.push({
                name: 'API Key & Network',
                passed: false,
                message: chalk.yellow(i18n.t('doctor.api_key_invalid'))
            });
        }
        else {
            results.push({
                name: 'API Key & Network',
                passed: false,
                message: chalk.yellow(i18n.t('doctor.network_error'))
            });
        }
    }
    await new Promise(resolve => setTimeout(resolve, 800));
    // Check 3: Git Env when using the windows platform and claude-code tool
    if (process.platform === 'win32' && toolManager.isToolInstalled('claude-code')) {
        spinner.text = i18n.t('doctor.check_git_env');
        const gitInstalled = toolManager.isGitInstalled();
        results.push({
            name: 'Git Environment',
            passed: gitInstalled,
            message: gitInstalled ? undefined : chalk.yellow(i18n.t('doctor.git_not_installed'))
        });
        await new Promise(resolve => setTimeout(resolve, 800));
    }
    // Check 4: GLM Coding Plan configuration
    spinner.text = i18n.t('doctor.check_glm_plan');
    const detectedConfig = claudeCodeManager.detectCurrentConfig();
    const configuredPlan = detectedConfig.plan || configManager.getPlan();
    const planConfigured = !!configuredPlan;
    let planMessage = '';
    if (planConfigured && configuredPlan) {
        const planName = configuredPlan === 'glm_coding_plan_global'
            ? 'GLM Coding Plan Global'
            : 'GLM Coding Plan China';
        planMessage = i18n.t('doctor.glm_plan_configured', { plan: planName });
    }
    else {
        planMessage = i18n.t('doctor.glm_plan_not_configured');
    }
    results.push({
        name: 'GLM Coding Plan',
        passed: planConfigured,
        message: planConfigured ? undefined : chalk.yellow(planMessage)
    });
    await new Promise(resolve => setTimeout(resolve, 800));
    // Check 5: Installed tools (检测所有支持的工具)
    spinner.text = i18n.t('doctor.check_tools');
    const supportedTools = toolManager.getSupportedTools();
    for (const tool of supportedTools) {
        const isInstalled = toolManager.isToolInstalled(tool.name);
        results.push({
            name: `Tool: ${tool.displayName} (${tool.name})`,
            passed: isInstalled,
            message: isInstalled ? undefined : chalk.yellow(i18n.t('doctor.tool_not_found', { tool: tool.displayName }))
        });
    }
    await new Promise(resolve => setTimeout(resolve, 800));
    spinner.stop();
    // Display results
    console.log(chalk.cyan.bold('\n=== Health Check Results ===\n'));
    let allPassed = true;
    for (const result of results) {
        const icon = result.passed ? chalk.green('✓') : chalk.red('✗');
        console.log(`${icon} ${result.name}`);
        if (result.message) {
            console.log(`  ${chalk.gray(result.message)}`);
        }
        if (!result.passed) {
            allPassed = false;
        }
    }
    console.log();
    if (allPassed) {
        console.log(chalk.green.bold(i18n.t('doctor.all_good')));
    }
    else {
        console.log(chalk.gray('\n' + i18n.t('doctor.suggestions') + ':'));
        console.log(chalk.gray('- Run "chelper init" to configure missing settings'));
        console.log(chalk.gray('- Check your network connection'));
        console.log(chalk.gray('- Ensure required tools are installed'));
    }
}
