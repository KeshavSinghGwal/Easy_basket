/**
 * Minimal RFC 4180 CSV reader/writer.
 *
 * Written by hand rather than pulled from npm because the project has no
 * CSV dependency and the requirement here is small and fixed.
 */

/**
 * Excel writes UTF-8 files with a byte-order mark and refuses to read
 * UTF-8 back without one. Devanagari and Gurmukhi arrive as mojibake
 * otherwise, so we strip it on read and emit it on write.
 */
export const UTF8_BOM = String.fromCharCode(0xFEFF);

export function parseCsv(input: string): string[][] {

    const text = input.charCodeAt(0) === 0xFEFF ? input.slice(1) : input;

    const rows: string[][] = [];

    let row: string[] = [];
    let field = "";
    let inQuotes = false;
    let i = 0;

    while (i < text.length) {

        const char = text[i];

        if (inQuotes) {

            if (char === '"') {

                /* "" is an escaped quote inside a quoted field */
                if (text[i + 1] === '"') {
                    field += '"';
                    i += 2;
                    continue;
                }

                inQuotes = false;
                i++;
                continue;
            }

            field += char;
            i++;
            continue;
        }

        if (char === '"') {
            inQuotes = true;
            i++;
            continue;
        }

        if (char === ",") {
            row.push(field);
            field = "";
            i++;
            continue;
        }

        if (char === "\r") {
            i++;
            continue;
        }

        if (char === "\n") {
            row.push(field);
            rows.push(row);
            row = [];
            field = "";
            i++;
            continue;
        }

        field += char;
        i++;
    }

    if (field.length > 0 || row.length > 0) {
        row.push(field);
        rows.push(row);
    }

    /* Drop fully blank lines */
    return rows.filter(
        r => r.some(cell => cell.trim() !== "")
    );
}

function escapeCell(value: unknown): string {

    const text = value == null ? "" : String(value);

    if (/[",\r\n]/.test(text))
        return `"${text.replace(/"/g, '""')}"`;

    return text;
}

export function toCsv(rows: unknown[][]): string {

    return rows
        .map(row => row.map(escapeCell).join(","))
        .join("\r\n");
}
