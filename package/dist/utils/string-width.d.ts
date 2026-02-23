/**
 * Calculate the visual display width of a string
 * Handles emoji, CJK characters, and ANSI escape codes
 */
/**
 * Strip ANSI escape codes from a string
 */
export declare function stripAnsi(str: string): string;
/**
 * Calculate the visual display width of a string
 * Strips ANSI codes and counts visual width of each character
 */
export declare function stringWidth(str: string): number;
/**
 * Pad a string to a specific visual width
 * @param str - The string to pad
 * @param targetWidth - The target visual width
 * @param char - The character to use for padding (default: space)
 * @param align - Alignment: 'left', 'right', or 'center' (default: 'left')
 */
export declare function padString(str: string, targetWidth: number, char?: string, align?: 'left' | 'right' | 'center'): string;
/**
 * Create a box border line
 * @param leftChar - Left border character
 * @param rightChar - Right border character
 * @param fillChar - Fill character
 * @param width - Total width including borders
 */
export declare function createBorderLine(leftChar: string, rightChar: string, fillChar: string, width: number): string;
/**
 * Create a box content line with borders
 * @param content - The content to display
 * @param leftChar - Left border character
 * @param rightChar - Right border character
 * @param width - Total width including borders
 * @param align - Content alignment
 */
export declare function createContentLine(content: string, leftChar: string, rightChar: string, width: number, align?: 'left' | 'right' | 'center'): string;
