#!/bin/bash

get_input() {
    [ -z "$2" ] && read -p "$1: " val && echo "$val" || echo "$2"
}

FUNCTION_NAME=$(get_input "Enter Function Name" "$1")
BUCKET_NAME=$(get_input "Enter S3 Bucket Name" "$2")
REGION=$(get_input "Enter AWS Region" "$3")

TIMESTAMP=$(date +%s)
FILE_NAME="full_feature_test_${TIMESTAMP}.pdf"

# This payload tests:
# 1. Puppeteer: Landscape mode, custom margins, headers/footers
# 2. Metadata: Title, Author, Keywords
# 3. Viewer: Hide toolbar, fit window
# 4. Encryption: User password '1234', printing DISABLED

PAYLOAD=$(cat <<EOF
{
  "bucketName": "$BUCKET_NAME",
  "fileName": "$FILE_NAME",
  "htmlBody": "<html><head><style>body { font-family: sans-serif; padding: 40px; background: #fdfdfd; } .warning { color: red; font-weight: bold; border: 2px solid red; padding: 10px; }</style></head><body><h1>Official Report</h1><div class='warning'>CONFIDENTIAL: READ ONLY</div><p>This document tests orientation, metadata, and security restrictions.</p><p>Try to PRINT this document - it should be disabled.</p></body></html>",

  "puppeteer": {
    "format": "Letter",
    "landscape": true,
    "printBackground": true,
    "displayHeaderFooter": true,
    "headerTemplate": "<div style='font-size:10px; width:100%; text-align:center;'>CLASSIFIED DOCUMENT</div>",
    "footerTemplate": "<div style='font-size:10px; width:100%; text-align:right; padding-right:1cm;'>Page <span class='pageNumber'></span></div>",
    "margin": { "top": "2cm", "bottom": "2cm", "right": "1cm", "left": "1cm" }
  },

  "pdfLib": {
    "metadata": {
      "title": "Full Feature Test",
      "author": "System Admin",
      "subject": "Lambda Capability Verification",
      "keywords": ["test", "aws", "security", "pdf"]
    },
    "viewerPreferences": {
      "hideToolbar": true,
      "fitWindow": true,
      "displayDocTitle": true
    },
    "encryption": {
      "userPassword": "1234",
      "ownerPassword": "admin_password_999",
      "permissions": {
        "printing": "none",
        "copying": false,
        "modifying": false,
        "annotating": false
      }
    }
  }
}
EOF
)

echo "---"
echo "Invoking $FUNCTION_NAME..."
echo "Target: s3://$BUCKET_NAME/$FILE_NAME"
echo "---"

aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    response.json

echo "Response:"
[ -f response.json ] && cat response.json && rm response.json
echo ""
echo "---"
echo "VERIFICATION STEPS:"
echo "1. Download s3://$BUCKET_NAME/$FILE_NAME"
echo "2. Open with password: '1234'"
echo "3. Verify document is LANDSCAPE."
echo "4. Verify header says 'CLASSIFIED DOCUMENT'."
echo "5. Verify PRINTING is DISABLED."