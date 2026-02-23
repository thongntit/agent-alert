/**
 * Calculate the visual display width of a string
 * Handles emoji, CJK characters, and ANSI escape codes
 */
/**
 * Strip ANSI escape codes from a string
 */
export function stripAnsi(str) {
    // eslint-disable-next-line no-control-regex
    return str.replace(/\u001b\[[0-9;]*m/g, '');
}
/**
 * Calculate the visual width of a character
 * - Emoji and wide characters (CJK): 2
 * - Regular ASCII: 1
 * - Zero-width characters: 0
 */
function charWidth(char) {
    const code = char.codePointAt(0);
    if (!code)
        return 0;
    // Zero-width characters
    if (code === 0x200b || // Zero-width space
        code === 0x200c || // Zero-width non-joiner
        code === 0x200d || // Zero-width joiner
        code === 0xfeff || // Zero-width no-break space
        (code >= 0xfe00 && code <= 0xfe0f) // Variation Selectors (emoji style selectors)
    ) {
        return 0;
    }
    // Emoji and symbols (rough approximation)
    // Most emoji are in these ranges and display as 2 characters wide
    if ((code >= 0x1f300 && code <= 0x1f9ff) || // Misc Symbols and Pictographs, Emoticons, etc.
        (code >= 0x2600 && code <= 0x26ff) || // Misc symbols
        (code >= 0x2700 && code <= 0x27bf) || // Dingbats
        (code >= 0x1f000 && code <= 0x1f02f) || // Mahjong Tiles, Domino Tiles
        (code >= 0x1f0a0 && code <= 0x1f0ff) // Playing Cards
    ) {
        return 2;
    }
    // CJK characters (Chinese, Japanese, Korean)
    // These are typically displayed as 2 characters wide
    if ((code >= 0x4e00 && code <= 0x9fff) || // CJK Unified Ideographs
        (code >= 0x3400 && code <= 0x4dbf) || // CJK Unified Ideographs Extension A
        (code >= 0x20000 && code <= 0x2a6df) || // CJK Unified Ideographs Extension B
        (code >= 0x2a700 && code <= 0x2b73f) || // CJK Unified Ideographs Extension C
        (code >= 0x2b740 && code <= 0x2b81f) || // CJK Unified Ideographs Extension D
        (code >= 0x2b820 && code <= 0x2ceaf) || // CJK Unified Ideographs Extension E
        (code >= 0xf900 && code <= 0xfaff) || // CJK Compatibility Ideographs
        (code >= 0x2f800 && code <= 0x2fa1f) || // CJK Compatibility Ideographs Supplement
        (code >= 0x3040 && code <= 0x309f) || // Hiragana
        (code >= 0x30a0 && code <= 0x30ff) || // Katakana
        (code >= 0xac00 && code <= 0xd7af) || // Hangul Syllables
        (code >= 0x1100 && code <= 0x11ff) || // Hangul Jamo
        (code >= 0x3130 && code <= 0x318f) || // Hangul Compatibility Jamo
        (code >= 0xa960 && code <= 0xa97f) || // Hangul Jamo Extended-A
        (code >= 0xd7b0 && code <= 0xd7ff) // Hangul Jamo Extended-B
    ) {
        return 2;
    }
    // Fullwidth characters
    if (code >= 0xff00 && code <= 0xffef) {
        return 2;
    }
    // Default to 1 for regular ASCII and other characters
    return 1;
}
/**
 * Calculate the visual display width of a string
 * Strips ANSI codes and counts visual width of each character
 */
export function stringWidth(str) {
    const cleaned = stripAnsi(str);
    let width = 0;
    // Use Array.from to properly handle surrogate pairs
    for (const char of Array.from(cleaned)) {
        width += charWidth(char);
    }
    return width;
}
/**
 * Pad a string to a specific visual width
 * @param str - The string to pad
 * @param targetWidth - The target visual width
 * @param char - The character to use for padding (default: space)
 * @param align - Alignment: 'left', 'right', or 'center' (default: 'left')
 */
export function padString(str, targetWidth, char = ' ', align = 'left') {
    const currentWidth = stringWidth(str);
    const padWidth = Math.max(0, targetWidth - currentWidth);
    if (padWidth === 0)
        return str;
    const padding = char.repeat(padWidth);
    if (align === 'right') {
        return padding + str;
    }
    else if (align === 'center') {
        const leftPad = Math.floor(padWidth / 2);
        const rightPad = padWidth - leftPad;
        return char.repeat(leftPad) + str + char.repeat(rightPad);
    }
    else {
        return str + padding;
    }
}
/**
 * Create a box border line
 * @param leftChar - Left border character
 * @param rightChar - Right border character
 * @param fillChar - Fill character
 * @param width - Total width including borders
 */
export function createBorderLine(leftChar, rightChar, fillChar, width) {
    const innerWidth = width - stringWidth(leftChar) - stringWidth(rightChar);
    return leftChar + fillChar.repeat(Math.max(0, innerWidth)) + rightChar;
}
/**
 * Create a box content line with borders
 * @param content - The content to display
 * @param leftChar - Left border character
 * @param rightChar - Right border character
 * @param width - Total width including borders
 * @param align - Content alignment
 */
export function createContentLine(content, leftChar, rightChar, width, align = 'left') {
    const borderWidth = stringWidth(leftChar) + stringWidth(rightChar);
    const innerWidth = width - borderWidth;
    const paddedContent = padString(content, innerWidth, ' ', align);
    return leftChar + paddedContent + rightChar;
}
