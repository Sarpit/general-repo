#!/bin/bash
#===============================================================================
# PDF Generation Script
# Description: Converts the markdown documentation to PDF format
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${SCRIPT_DIR}/vllm-technical-guide.md"
OUTPUT_FILE="${SCRIPT_DIR}/vllm-technical-guide.pdf"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PDF Generation for vLLM Technical Guide${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}Input:  ${INPUT_FILE}${NC}"
echo -e "${YELLOW}Output: ${OUTPUT_FILE}${NC}"
echo ""

#===============================================================================
# Method 1: Using pandoc (recommended)
#===============================================================================
generate_with_pandoc() {
    echo -e "${CYAN}Generating PDF with pandoc...${NC}"

    pandoc "$INPUT_FILE" \
        -o "$OUTPUT_FILE" \
        --pdf-engine=xelatex \
        -V geometry:margin=1in \
        -V fontsize=11pt \
        -V documentclass=article \
        --toc \
        --toc-depth=2 \
        --highlight-style=tango \
        -V colorlinks=true \
        -V linkcolor=blue \
        -V urlcolor=blue \
        -V toccolor=gray

    echo -e "${GREEN}✓ PDF generated successfully: ${OUTPUT_FILE}${NC}"
}

#===============================================================================
# Method 2: Using grip + wkhtmltopdf (alternative)
#===============================================================================
generate_with_grip() {
    echo -e "${CYAN}Generating PDF with grip + wkhtmltopdf...${NC}"

    # First convert to HTML using grip
    HTML_FILE="${SCRIPT_DIR}/vllm-technical-guide.html"

    grip "$INPUT_FILE" --export "$HTML_FILE"

    # Then convert HTML to PDF
    wkhtmltopdf \
        --enable-local-file-access \
        --page-size A4 \
        --margin-top 20mm \
        --margin-bottom 20mm \
        --margin-left 15mm \
        --margin-right 15mm \
        "$HTML_FILE" \
        "$OUTPUT_FILE"

    # Clean up HTML
    rm -f "$HTML_FILE"

    echo -e "${GREEN}✓ PDF generated successfully: ${OUTPUT_FILE}${NC}"
}

#===============================================================================
# Method 3: Using marked + puppeteer (Node.js)
#===============================================================================
generate_with_node() {
    echo -e "${CYAN}Generating PDF with Node.js...${NC}"

    node << 'NODEJS_SCRIPT'
const fs = require('fs');
const path = require('path');
const { marked } = require('marked');
const puppeteer = require('puppeteer');

const scriptDir = process.env.SCRIPT_DIR || __dirname;
const inputFile = path.join(scriptDir, 'vllm-technical-guide.md');
const outputFile = path.join(scriptDir, 'vllm-technical-guide.pdf');

async function generatePDF() {
    const markdown = fs.readFileSync(inputFile, 'utf-8');
    const html = marked(markdown);

    const fullHtml = `
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                max-width: 900px;
                margin: 0 auto;
                padding: 20px;
            }
            h1, h2, h3 { color: #333; }
            code {
                background: #f4f4f4;
                padding: 2px 6px;
                border-radius: 3px;
                font-family: 'Monaco', 'Menlo', monospace;
            }
            pre {
                background: #f4f4f4;
                padding: 15px;
                border-radius: 5px;
                overflow-x: auto;
            }
            table {
                border-collapse: collapse;
                width: 100%;
                margin: 20px 0;
            }
            th, td {
                border: 1px solid #ddd;
                padding: 10px;
                text-align: left;
            }
            th { background: #f4f4f4; }
        </style>
    </head>
    <body>${html}</body>
    </html>`;

    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.setContent(fullHtml, { waitUntil: 'networkidle0' });
    await page.pdf({
        path: outputFile,
        format: 'A4',
        margin: { top: '20mm', right: '15mm', bottom: '20mm', left: '15mm' }
    });
    await browser.close();

    console.log('PDF generated:', outputFile);
}

generatePDF().catch(console.error);
NODEJS_SCRIPT

    echo -e "${GREEN}✓ PDF generated successfully: ${OUTPUT_FILE}${NC}"
}

#===============================================================================
# Method 4: Simple HTML conversion (fallback - no dependencies)
#===============================================================================
generate_simple_html() {
    echo -e "${CYAN}Generating HTML file (open in browser and print to PDF)...${NC}"

    HTML_FILE="${SCRIPT_DIR}/vllm-technical-guide.html"

    cat > "$HTML_FILE" << 'HTMLHEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>vLLM Technical Guide</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            line-height: 1.7;
            max-width: 900px;
            margin: 0 auto;
            padding: 40px 20px;
            color: #333;
        }
        h1 { color: #1a1a2e; border-bottom: 3px solid #4a4e69; padding-bottom: 10px; }
        h2 { color: #22223b; border-bottom: 1px solid #9a8c98; padding-bottom: 8px; margin-top: 40px; }
        h3 { color: #4a4e69; }
        code {
            background: #f4f3ee;
            padding: 3px 8px;
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Menlo', 'Consolas', monospace;
            font-size: 0.9em;
        }
        pre {
            background: #22223b;
            color: #f2e9e4;
            padding: 20px;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 0.85em;
        }
        pre code {
            background: none;
            padding: 0;
            color: inherit;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 25px 0;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        th, td {
            border: 1px solid #c9ada7;
            padding: 12px 15px;
            text-align: left;
        }
        th {
            background: #4a4e69;
            color: white;
            font-weight: 600;
        }
        tr:nth-child(even) { background: #f4f3ee; }
        blockquote {
            border-left: 4px solid #9a8c98;
            margin: 20px 0;
            padding: 10px 20px;
            background: #f4f3ee;
        }
        hr {
            border: none;
            border-top: 2px solid #c9ada7;
            margin: 40px 0;
        }
        @media print {
            body { max-width: none; padding: 0; }
            pre { white-space: pre-wrap; word-wrap: break-word; }
        }
    </style>
</head>
<body>
HTMLHEADER

    # Simple markdown to HTML conversion using sed/awk
    # This is a basic converter - for full markdown support use pandoc

    cat "$INPUT_FILE" | \
    # Headers
    sed 's/^### \(.*\)/<h3>\1<\/h3>/' | \
    sed 's/^## \(.*\)/<h2>\1<\/h2>/' | \
    sed 's/^# \(.*\)/<h1>\1<\/h1>/' | \
    # Code blocks (simplified)
    sed 's/^```.*/<pre><code>/g' | \
    sed 's/^```/<\/code><\/pre>/g' | \
    # Inline code
    sed 's/`\([^`]*\)`/<code>\1<\/code>/g' | \
    # Bold
    sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g' | \
    # Horizontal rules
    sed 's/^---$/<hr>/g' | \
    # Line breaks for paragraphs
    sed 's/^$/<br><br>/' \
    >> "$HTML_FILE"

    cat >> "$HTML_FILE" << 'HTMLFOOTER'
</body>
</html>
HTMLFOOTER

    echo -e "${GREEN}✓ HTML generated: ${HTML_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}To create PDF:${NC}"
    echo "  1. Open ${HTML_FILE} in your browser"
    echo "  2. Press Cmd+P (Mac) or Ctrl+P (Windows/Linux)"
    echo "  3. Select 'Save as PDF' as the destination"
    echo ""
}

#===============================================================================
# Main: Try different methods based on available tools
#===============================================================================

echo -e "${YELLOW}Checking available PDF generation tools...${NC}"
echo ""

if command -v pandoc &> /dev/null && command -v xelatex &> /dev/null; then
    echo -e "${GREEN}✓ Found: pandoc + xelatex${NC}"
    generate_with_pandoc
elif command -v pandoc &> /dev/null; then
    echo -e "${GREEN}✓ Found: pandoc (using default engine)${NC}"
    pandoc "$INPUT_FILE" -o "$OUTPUT_FILE" --toc -V geometry:margin=1in
    echo -e "${GREEN}✓ PDF generated: ${OUTPUT_FILE}${NC}"
elif command -v grip &> /dev/null && command -v wkhtmltopdf &> /dev/null; then
    echo -e "${GREEN}✓ Found: grip + wkhtmltopdf${NC}"
    generate_with_grip
elif command -v node &> /dev/null && npm list puppeteer &> /dev/null 2>&1; then
    echo -e "${GREEN}✓ Found: Node.js + puppeteer${NC}"
    SCRIPT_DIR="$SCRIPT_DIR" generate_with_node
else
    echo -e "${YELLOW}No PDF tools found. Generating HTML instead.${NC}"
    echo ""
    echo -e "${CYAN}To install PDF generation tools:${NC}"
    echo ""
    echo "  # Option 1: pandoc (recommended)"
    echo "  brew install pandoc"
    echo "  brew install --cask mactex  # for xelatex"
    echo ""
    echo "  # Option 2: wkhtmltopdf"
    echo "  brew install wkhtmltopdf"
    echo "  pip install grip"
    echo ""
    echo "  # Option 3: Node.js"
    echo "  npm install -g puppeteer marked"
    echo ""

    generate_simple_html
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Done!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
