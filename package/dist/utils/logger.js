import { existsSync, mkdirSync, appendFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
export var LogLevel;
(function (LogLevel) {
    LogLevel[LogLevel["DEBUG"] = 0] = "DEBUG";
    LogLevel[LogLevel["INFO"] = 1] = "INFO";
    LogLevel[LogLevel["WARN"] = 2] = "WARN";
    LogLevel[LogLevel["ERROR"] = 3] = "ERROR";
})(LogLevel || (LogLevel = {}));
// Sensitive keys that should be masked in logs
const SENSITIVE_KEYS = [
    'token',
    'apikey',
    'api_key',
    'api-key',
    'auth_token',
    'auth-token',
    'authorization',
    'password',
    'secret',
    'credential',
    'anthropic_auth_token',
    'anthropic_api_key',
    'z_ai_api_key'
];
// Regex patterns for detecting sensitive values
const SENSITIVE_PATTERNS = [
    // JWT-like tokens
    /eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
    // API key patterns (common formats)
    /\b[a-zA-Z0-9]{32,}\b/g,
    // Bearer token in headers
    /Bearer\s+[A-Za-z0-9._-]+/gi
];
export class Logger {
    static instance;
    logLevel = LogLevel.INFO;
    fileLogLevel = LogLevel.WARN;
    logDir;
    fileLoggingEnabled = true;
    constructor() {
        this.logDir = join(homedir(), '.chelper');
        this.ensureLogDir();
    }
    static getInstance() {
        if (!Logger.instance) {
            Logger.instance = new Logger();
        }
        return Logger.instance;
    }
    /**
     * Ensure the log directory exists
     */
    ensureLogDir() {
        try {
            if (!existsSync(this.logDir)) {
                mkdirSync(this.logDir, { recursive: true });
            }
        }
        catch (error) {
            this.fileLoggingEnabled = false;
        }
    }
    /**
     * Get the current log file path based on today's date
     */
    getLogFilePath() {
        const now = new Date();
        const dateStr = now.toISOString().split('T')[0]; // yyyy-mm-dd
        return join(this.logDir, `${dateStr}.log`);
    }
    /**
     * Sanitize a value to mask sensitive information
     */
    sanitizeValue(value) {
        if (value === null || value === undefined) {
            return value;
        }
        if (typeof value === 'string') {
            let sanitized = value;
            // Apply regex patterns to mask sensitive values
            for (const pattern of SENSITIVE_PATTERNS) {
                sanitized = sanitized.replace(pattern, '[REDACTED]');
            }
            return sanitized;
        }
        if (Array.isArray(value)) {
            return value.map(item => this.sanitizeValue(item));
        }
        if (typeof value === 'object') {
            const sanitized = {};
            for (const [key, val] of Object.entries(value)) {
                const keyLower = key.toLowerCase();
                const isSensitive = SENSITIVE_KEYS.some(sk => keyLower.includes(sk));
                sanitized[key] = isSensitive ? '[REDACTED]' : this.sanitizeValue(val);
            }
            return sanitized;
        }
        return value;
    }
    /**
     * Sanitize message and args to remove sensitive information
     */
    sanitize(message, args) {
        const sanitizedMessage = this.sanitizeValue(message);
        const sanitizedArgs = args.map(arg => this.sanitizeValue(arg));
        return { message: sanitizedMessage, args: sanitizedArgs };
    }
    /**
     * Format args to string for file logging
     */
    formatArgs(args) {
        if (args.length === 0)
            return '';
        return ' ' + args.map(arg => {
            if (typeof arg === 'object') {
                try {
                    return JSON.stringify(arg);
                }
                catch {
                    return String(arg);
                }
            }
            return String(arg);
        }).join(' ');
    }
    /**
     * Write log entry to file
     */
    writeToFile(level, message, args) {
        if (!this.fileLoggingEnabled)
            return;
        try {
            const { message: sanitizedMsg, args: sanitizedArgs } = this.sanitize(message, args);
            const timestamp = new Date().toISOString();
            const logEntry = `${timestamp} [${level}] ${sanitizedMsg}${this.formatArgs(sanitizedArgs)}\n`;
            appendFileSync(this.getLogFilePath(), logEntry, 'utf-8');
        }
        catch {
            // Silently fail if file writing fails
        }
    }
    setLogLevel(level) {
        this.logLevel = level;
    }
    setFileLogLevel(level) {
        this.fileLogLevel = level;
    }
    setFileLoggingEnabled(enabled) {
        this.fileLoggingEnabled = enabled;
    }
    debug(message, ...args) {
        if (this.logLevel <= LogLevel.DEBUG) {
            console.debug(`[DEBUG] ${message}`, ...args);
        }
        if (this.fileLoggingEnabled && this.fileLogLevel <= LogLevel.DEBUG) {
            this.writeToFile('DEBUG', message, args);
        }
    }
    info(message, ...args) {
        if (this.logLevel <= LogLevel.INFO) {
            console.info(`[INFO] ${message}`, ...args);
        }
        if (this.fileLoggingEnabled && this.fileLogLevel <= LogLevel.INFO) {
            this.writeToFile('INFO', message, args);
        }
    }
    warn(message, ...args) {
        if (this.logLevel <= LogLevel.WARN) {
            console.warn(`[WARN] ${message}`, ...args);
        }
        if (this.fileLoggingEnabled && this.fileLogLevel <= LogLevel.WARN) {
            this.writeToFile('WARN', message, args);
        }
    }
    error(message, ...args) {
        if (this.logLevel <= LogLevel.ERROR) {
            console.error(`[ERROR] ${message}`, ...args);
        }
        if (this.fileLoggingEnabled && this.fileLogLevel <= LogLevel.ERROR) {
            this.writeToFile('ERROR', message, args);
        }
    }
    /**
     * Log an error with stack trace (always writes to file)
     */
    logError(context, error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        const stack = error instanceof Error ? error.stack : undefined;
        // Write to file with sanitized info
        this.writeToFile('ERROR', `[${context}] ${errorMessage}`, stack ? [{ stack }] : []);
    }
    /**
     * Get the log directory path
     */
    getLogDir() {
        return this.logDir;
    }
}
export const logger = Logger.getInstance();
