export declare enum LogLevel {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3
}
export declare class Logger {
    private static instance;
    private logLevel;
    private fileLogLevel;
    private logDir;
    private fileLoggingEnabled;
    private constructor();
    static getInstance(): Logger;
    /**
     * Ensure the log directory exists
     */
    private ensureLogDir;
    /**
     * Get the current log file path based on today's date
     */
    private getLogFilePath;
    /**
     * Sanitize a value to mask sensitive information
     */
    private sanitizeValue;
    /**
     * Sanitize message and args to remove sensitive information
     */
    private sanitize;
    /**
     * Format args to string for file logging
     */
    private formatArgs;
    /**
     * Write log entry to file
     */
    private writeToFile;
    setLogLevel(level: LogLevel): void;
    setFileLogLevel(level: LogLevel): void;
    setFileLoggingEnabled(enabled: boolean): void;
    debug(message: string, ...args: any[]): void;
    info(message: string, ...args: any[]): void;
    warn(message: string, ...args: any[]): void;
    error(message: string, ...args: any[]): void;
    /**
     * Log an error with stack trace (always writes to file)
     */
    logError(context: string, error: unknown): void;
    /**
     * Get the log directory path
     */
    getLogDir(): string;
}
export declare const logger: Logger;
