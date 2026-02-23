#!/usr/bin/env node
import { Command } from './lib/command.js';
import { i18n } from './lib/i18n.js';
import { logger } from './utils/logger.js';
async function main() {
    const args = process.argv.slice(2);
    const command = new Command();
    try {
        await command.execute(args);
    }
    catch (error) {
        logger.logError('CLI', error);
        console.error(`${i18n.t('cli.error_general')}`, error instanceof Error ? error.message : String(error));
        process.exit(1);
    }
}
main();
