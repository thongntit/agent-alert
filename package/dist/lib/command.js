import { Command as Commander } from 'commander';
import { i18n } from './i18n.js';
import { configManager } from './config.js';
import { wizard } from './wizard.js';
import { langCommand, authCommand, doctorCommand, configCommand } from '../commands/index.js';
import chalk from 'chalk';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
export class Command {
    program;
    constructor() {
        // Load language from config
        const lang = configManager.getLang();
        i18n.loadFromConfig(lang);
        this.program = new Commander();
        this.setupProgram();
    }
    getVersion() {
        try {
            const __filename = fileURLToPath(import.meta.url);
            const __dirname = dirname(__filename);
            const packagePath = join(__dirname, '../../package.json');
            const packageJson = JSON.parse(readFileSync(packagePath, 'utf-8'));
            return packageJson.version;
        }
        catch {
            return '1.0.0';
        }
    }
    setupProgram() {
        this.program
            .name('chelper')
            .description(i18n.t('cli.title'))
            .version(this.getVersion(), '-v, --version', i18n.t('commands.version'))
            .helpOption('-h, --help', i18n.t('commands.help'));
        // Init command - interactive wizard
        this.program
            .command('init')
            .description(i18n.t('commands.init'))
            .action(async () => {
            await this.handleInitCommand();
        });
        // Lang command - language management
        const langCmd = this.program
            .command('lang')
            .description(i18n.t('commands.lang'));
        langCmd
            .command('show')
            .description(i18n.t('lang.show_usage'))
            .action(async () => {
            await langCommand(['show']);
        });
        langCmd
            .command('set <locale>')
            .description(i18n.t('lang.set_usage'))
            .action(async (locale) => {
            await langCommand(['set', locale]);
        });
        // Auth command - API key management
        const authCmd = this.program
            .command('auth')
            .description(i18n.t('commands.auth'));
        authCmd
            .argument('[service]', 'Service type: glm_coding_plan_global or glm_coding_plan_china')
            .argument('[token]', 'API token')
            .action(async (service, token) => {
            const args = [];
            if (service)
                args.push(service);
            if (token)
                args.push(token);
            await authCommand(args);
        });
        authCmd
            .command('revoke')
            .description('Revoke saved API key')
            .action(async () => {
            await authCommand(['revoke']);
        });
        authCmd
            .command('reload <tool>')
            .description('Reload plan configuration to the specified tool (e.g., claude)')
            .action(async (tool) => {
            await authCommand(['reload', tool]);
        });
        // Doctor command - health check
        this.program
            .command('doctor')
            .description(i18n.t('commands.doctor'))
            .action(async () => {
            await doctorCommand();
        });
        // Config command - tool configuration
        const enterCmd = this.program
            .command('enter [option]')
            .description(i18n.t('commands.enter'));
        // config 子命令
        enterCmd
            .action(async (option) => {
            // 如果没有参数，显示主菜单
            if (!option) {
                await wizard.showMainMenu();
                return;
            }
            // 根据参数执行对应操作
            switch (option) {
                case 'lang':
                case 'language':
                    await wizard.configLanguage();
                    break;
                case 'plan':
                    await wizard.configPlan();
                    break;
                case 'apikey':
                case 'api-key':
                    await wizard.configApiKey();
                    break;
                default: {
                    // 尝试作为工具名处理
                    const args = [option];
                    await configCommand(args);
                    break;
                }
            }
        });
        this.program.action(async () => {
            if (configManager.isFirstRun()) {
                console.log(chalk.cyan(i18n.t('messages.first_run')));
                await wizard.runFirstTimeSetup();
            }
            else {
                await wizard.showMainMenu();
            }
        });
        // Custom help
        this.program.configureHelp({
            sortSubcommands: true,
            subcommandTerm: (cmd) => cmd.name() + ' ' + cmd.usage()
        });
        // Add examples to help
        this.program.addHelpText('after', `
${chalk.bold(i18n.t('cli.examples'))}:
  ${chalk.gray('$ chelper                    # Interactive main menu')}
  ${chalk.gray('$ chelper init               # Run first-time setup wizard')}
  ${chalk.gray('$ chelper enter              # Interactive main menu')}
  ${chalk.gray('$ chelper enter lang         # Interactive language configuration')}
  ${chalk.gray('$ chelper enter plan         # Interactive plan configuration')}
  ${chalk.gray('$ chelper enter apikey       # Interactive API key configuration')}
  ${chalk.gray('$ chelper enter claude-code  # Interactive Configure Claude Code tool')}
  ${chalk.gray('$ chelper lang show          # Show current language')}
  ${chalk.gray('$ chelper lang set zh_CN')}
  ${chalk.gray('$ chelper auth               # Interactive auth setup')}
  ${chalk.gray('$ chelper auth glm_coding_plan_global <token>      # Set API key for global plan')}
  ${chalk.gray('$ chelper auth glm_coding_plan_china <token>       # Set API key for china plan')}
  ${chalk.gray('$ chelper auth revoke')}
  ${chalk.gray('$ chelper auth reload claude # Reload plan config to Claude Code')}
  ${chalk.gray('$ chelper doctor             # Health check')}
`);
    }
    async handleInitCommand() {
        await wizard.runFirstTimeSetup();
    }
    async execute(args) {
        try {
            await this.program.parseAsync(args, { from: 'user' });
        }
        catch (error) {
            if (error instanceof Error) {
                console.error(chalk.red(i18n.t('cli.error_general')), error.message);
            }
            process.exit(1);
        }
    }
    getProgram() {
        return this.program;
    }
}
