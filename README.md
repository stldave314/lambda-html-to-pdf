# Lambda HTML to PDF Setup

1. Install AWS CLI and run `aws configure` to setup access to AWS with your credentials
2. Create an IAM Role to access the S3 bucket from the Lambda function by running `./create-role.sh`. Be sure to document the ARN of the new role output by the script.
3. Publish an AWS Lambda Layer with Chromium to render the HTML by running `./publish-layer.sh`. Be sure to document the ARN of the Lambda Layer output by the script.
4. Deploy the package to AWS Lambda by running `./deploy.sh`
5. Test the AWS Lambda function by running `./test-lambda.sh`
6. Create an AWS API Gateway Endpoint by running `./setup-api.sh`
7. Manage the AWS API Gateway API Keys by running `manage-keys.sh`

-----

# Lambda HTML to PDF API

This Lambda function renders HTML into a PDF using Puppeteer, with support for advanced metadata, viewer preferences, and security encryption (password protection and permissions).

## Endpoint Overview

* **Method:** `POST`
* **Content-Type:** `application/json`
* **Auth:** Requires `x-api-key` header.

-----

## JSON Payload Structure

The input payload is a JSON object with the following top-level fields:

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `htmlBody` | `string` | **Yes** | The full HTML content to render. CSS/Images must be inline (base64) or accessible. |
| `fileName` | `string` | **Yes** | The desired filename (e.g., `report.pdf`). |
| `bucketName` | `string` | **Yes** | The S3 bucket where the file will be saved. |
| `puppeteer` | `object` | No | Rendering options (margins, orientation, format). |
| `pdfLib` | `object` | No | Post-processing options (metadata, encryption, viewer settings). |

-----

## 1\. Puppeteer Options (`puppeteer`)

Controls how the browser renders the PDF.

```json
"puppeteer": {
  "format": "Letter",
  "landscape": true,
  "printBackground": true,
  "margin": { "top": "1cm", "right": "1cm", "bottom": "1cm", "left": "1cm" },
  "scale": 1.0,
  "displayHeaderFooter": false
}
```

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `format` | `string` | `"Letter"` | Page size. Valid: `Letter`, `Legal`, `Tabloid`, `A0`–`A6`. |
| `landscape` | `boolean` | `false` | `true` for horizontal orientation, `false` for vertical. |
| `printBackground` | `boolean` | `true` | Set `false` to suppress background colors/images. |
| `scale` | `number` | `1.0` | Scale of the webpage rendering (0.1 to 2.0). |
| `margin` | `object` | `1cm` (all) | Object with `top`, `right`, `bottom`, `left`. Units: `px`, `cm`, `in`. |
| `displayHeaderFooter`| `boolean` | `false` | `true` to show headers/footers. |
| `headerTemplate` | `string` | `""` | HTML for header. Supports variables: `<span class='pageNumber'></span>`, `<span class='totalPages'></span>`, `<span class='date'></span>`, `<span class='title'></span>`. |
| `footerTemplate` | `string` | `""` | HTML for footer. Same variables as header. |
| `pageRanges` | `string` | All | Specific pages to print (e.g., `"1-5, 8, 11-13"`). |
| `preferCSSPageSize` | `boolean` | `false` | If `true`, prioritize `@page` CSS rules over the `format` option. |

-----

## 2\. Metadata Options (`pdfLib.metadata`)

Sets standard PDF properties visible in document properties.

```json
"pdfLib": {
  "metadata": {
    "title": "Quarterly Report",
    "author": "Finance Dept",
    "subject": "Q3 Financials",
    "keywords": ["finance", "2025", "confidential"],
    "creator": "My App v2.0",
    "creationDate": "2025-12-13T12:00:00Z"
  }
}
```

| Option | Type | Description |
| :--- | :--- | :--- |
| `title` | `string` | The document title. |
| `author` | `string` | The name of the person/entity creating the file. |
| `subject` | `string` | The subject matter description. |
| `keywords` | `array` | List of keywords strings. |
| `creator` | `string` | The name of the app that created the original content. |
| `producer` | `string` | The name of the app that converted it to PDF. |
| `creationDate` | `string` | ISO 8601 Date string (e.g., `2025-01-01T00:00:00Z`). |
| `modificationDate`| `string` | ISO 8601 Date string. |

-----

## 3\. Viewer Preferences (`pdfLib.viewerPreferences`)

Controls how the PDF opens in the user's viewer (e.g., Adobe Acrobat).

```json
"pdfLib": {
  "viewerPreferences": {
    "hideToolbar": true,
    "fitWindow": true
  }
}
```

| Option | Type | Description |
| :--- | :--- | :--- |
| `hideToolbar` | `boolean` | Hides the viewer's toolbar (save, print buttons, etc.). |
| `hideMenubar` | `boolean` | Hides the viewer's menu bar (File, Edit, etc.). |
| `hideWindowUI` | `boolean` | Hides UI elements like scrollbars. |
| `fitWindow` | `boolean` | Resizes the window to fit the document page size. |
| `centerWindow` | `boolean` | Positions the window in the center of the screen. |
| `displayDocTitle` | `boolean` | Shows the Document `Title` in the title bar instead of the filename. |

-----

## 4\. Encryption & Permissions (`pdfLib.encryption`)

Secures the PDF with 128-bit RC4 encryption.

**Important:** To enforce `permissions`, you **must** provide an `ownerPassword` different from the `userPassword`.

```json
"pdfLib": {
  "encryption": {
    "userPassword": "reader123",
    "ownerPassword": "admin456",
    "permissions": {
      "printing": "none",
      "copying": false
    }
  }
}
```

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `userPassword` | `string` | `""` | Password required to **open** the file. |
| `ownerPassword` | `string` | `""` | Password required to **change permissions**. |
| `permissions` | `object` | *Allowed* | See table below. |

### Permission Flags

| Flag | Type | Values | Description |
| :--- | :--- | :--- | :--- |
| `printing` | `string` | `'highResolution'`, `'lowResolution'`, `'none'` | Controls printing ability. |
| `modifying` | `boolean` | `true` / `false` | Allow modifying document content. |
| `copying` | `boolean` | `true` / `false` | Allow selecting and copying text/images. |
| `annotating` | `boolean` | `true` / `false` | Allow adding comments/annotations. |
| `fillingForms` | `boolean` | `true` / `false` | Allow filling in form fields. |
| `contentAccessibility`| `boolean` | `true` / `false` | Allow screen readers to access text. |
| `documentAssembly` | `boolean` | `true` / `false` | Allow inserting/rotating/deleting pages. |

-----

## Example Payload (Full Feature)

```json
{
  "bucketName": "my-reports-bucket",
  "fileName": "secure_report_001.pdf",
  "htmlBody": "<html><body><h1>Confidential</h1></body></html>",
  
  "puppeteer": {
    "format": "A4",
    "landscape": true,
    "margin": { "top": "2cm", "bottom": "2cm", "left": "1cm", "right": "1cm" },
    "displayHeaderFooter": true,
    "headerTemplate": "<div style='font-size:10px;'>SECRET</div>",
    "footerTemplate": "<div style='font-size:10px;'>Page <span class='pageNumber'></span></div>"
  },
  
  "pdfLib": {
    "metadata": {
      "title": "Q3 Secret Report",
      "author": "Chief Financial Officer"
    },
    "viewerPreferences": {
      "hideToolbar": true,
      "displayDocTitle": true
    },
    "encryption": {
      "userPassword": "password123",
      "ownerPassword": "admin_password_999",
      "permissions": {
        "printing": "none",
        "copying": false,
        "modifying": false
      }
    }
  }
}
```