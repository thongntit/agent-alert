import { Command as Commander } from 'commander';
export declare class Command {
    private program;
    constructor();
    private getVersion;
    private setupProgram;
    private handleInitCommand;
    execute(args: string[]): Promise<void>;
    getProgram(): Commander;
}
