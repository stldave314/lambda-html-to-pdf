const chromium = require('@sparticuz/chromium');
const puppeteer = require('puppeteer-core');
const { PDFDocument } = require('pdf-lib');
const { encryptPDF } = require('@pdfsmaller/pdf-encrypt-lite');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({});

/**
 * =========================================================================================
 * DOCUMENTATION OF AVAILABLE OPTIONS
 * =========================================================================================
 * * 1. PUPPETEER OPTIONS (payload.puppeteer)
 * ----------------------------------------
 * format:              'Letter' (default), 'Legal', 'Tabloid', 'A0', 'A1', 'A2', 'A3', 'A4', 'A5', 'A6'
 * landscape:           true | false (default)
 * printBackground:     true (default) | false
 * scale:               0.1 to 2.0 (default 1)
 * displayHeaderFooter: true | false (default)
 * headerTemplate:      HTML string for header. Usage: <span class="title"></span>, <span class="date"></span>, <span class="pageNumber"></span>
 * footerTemplate:      HTML string for footer.
 * margin:              Object { top, right, bottom, left } e.g., "1cm", "20px"
 * pageRanges:          String "1-5, 8, 11-13" (default: all pages)
 * preferCSSPageSize:   true | false (default) - Priority to @page CSS rules over 'format' option
 * * 2. METADATA OPTIONS (payload.pdfLib.metadata)
 * ---------------------------------------------
 * title:               String
 * author:              String
 * subject:             String
 * keywords:            Array of Strings ["invoice", "2025"]
 * creator:             String (Software that created it)
 * producer:            String (Software that converted it)
 * creationDate:        ISO Date String (e.g., "2025-12-13T12:00:00Z")
 * modificationDate:    ISO Date String
 * * 3. VIEWER PREFERENCES (payload.pdfLib.viewerPreferences)
 * --------------------------------------------------------
 * hideToolbar:         true | false - Hides the viewer toolbar
 * hideMenubar:         true | false - Hides the viewer menu bar
 * hideWindowUI:        true | false - Hides UI elements like scrollbars
 * fitWindow:           true | false - Resizes window to fit document
 * centerWindow:        true | false - Positions window in center of screen
 * displayDocTitle:     true | false - Shows 'Title' in window bar instead of filename
 * * 4. ENCRYPTION & PERMISSIONS (payload.pdfLib.encryption)
 * -------------------------------------------------------
 * userPassword:        String - Password to OPEN the file
 * ownerPassword:       String - Password to CHANGE permissions (Required if setting permissions)
 * permissions:         Object {
 * printing:            'highResolution' | 'lowResolution' | 'none'
 * modifying:           true | false
 * copying:             true | false (Copy text/images)
 * annotating:          true | false (Add comments)
 * fillingForms:        true | false
 * contentAccessibility:true | false (Screen readers)
 * documentAssembly:    true | false (Combine/Insert pages)
 * }
 * =========================================================================================
 */

exports.handler = async (event) => {
    let browser = null;

    try {
        const payload = typeof event.body === 'string' ? JSON.parse(event.body) : event;
        const {
            htmlBody,
            fileName,
            bucketName,
            puppeteer: puppeteerOpts = {},
            pdfLib: pdfLibOpts = {}
        } = payload;

        if (!htmlBody || !fileName || !bucketName) {
            throw new Error('Missing required inputs: htmlBody, fileName, or bucketName');
        }

        // --- PHASE 1: RENDER HTML (Puppeteer) ---
        // Graphics mode disabled for Node 20 / Amazon Linux 2023 compatibility
        chromium.setGraphicsMode = false;

        browser = await puppeteer.launch({
            args: chromium.args,
            defaultViewport: chromium.defaultViewport,
            executablePath: await chromium.executablePath(),
            headless: chromium.headless,
        });

        const page = await browser.newPage();
        await page.setContent(htmlBody, { waitUntil: 'networkidle0' });

        // Map payload options to Puppeteer configuration
        const pdfConfig = {
            format: puppeteerOpts.format || 'Letter',
            landscape: puppeteerOpts.landscape || false,
            printBackground: puppeteerOpts.printBackground !== false, // default true
            scale: puppeteerOpts.scale || 1,
            margin: puppeteerOpts.margin || { top: '1cm', right: '1cm', bottom: '1cm', left: '1cm' },
            displayHeaderFooter: puppeteerOpts.displayHeaderFooter || false,
            headerTemplate: puppeteerOpts.headerTemplate || '',
            footerTemplate: puppeteerOpts.footerTemplate || '',
            pageRanges: puppeteerOpts.pageRanges || '',
            preferCSSPageSize: puppeteerOpts.preferCSSPageSize || false
        };

        const pdfBuffer = await page.pdf(pdfConfig);

        // --- PHASE 2: METADATA & PREFERENCES (pdf-lib) ---
        const pdfDoc = await PDFDocument.load(pdfBuffer);

        // A. Apply Metadata
        if (pdfLibOpts.metadata) {
            const m = pdfLibOpts.metadata;
            if (m.title) pdfDoc.setTitle(m.title);
            if (m.author) pdfDoc.setAuthor(m.author);
            if (m.subject) pdfDoc.setSubject(m.subject);
            if (m.keywords && Array.isArray(m.keywords)) pdfDoc.setKeywords(m.keywords);
            if (m.creator) pdfDoc.setCreator(m.creator);
            if (m.producer) pdfDoc.setProducer(m.producer);
            if (m.creationDate) pdfDoc.setCreationDate(new Date(m.creationDate));
            if (m.modificationDate) pdfDoc.setModificationDate(new Date(m.modificationDate));
        }

        // B. Apply Viewer Preferences
        if (pdfLibOpts.viewerPreferences) {
            const prefs = pdfDoc.catalog.getOrCreateViewerPreferences();
            const vp = pdfLibOpts.viewerPreferences;
            if (vp.hideToolbar) prefs.setHideToolbar(vp.hideToolbar);
            if (vp.hideMenubar) prefs.setHideMenubar(vp.hideMenubar);
            if (vp.hideWindowUI) prefs.setHideWindowUI(vp.hideWindowUI);
            if (vp.fitWindow) prefs.setFitWindow(vp.fitWindow);
            if (vp.centerWindow) prefs.setCenterWindow(vp.centerWindow);
            if (vp.displayDocTitle) prefs.setDisplayDocTitle(vp.displayDocTitle);
        }

        let finalPdfBytes = await pdfDoc.save();

        // --- PHASE 3: ENCRYPTION (pdf-encrypt-lite) ---
        if (pdfLibOpts.encryption) {
            const enc = pdfLibOpts.encryption;

            // Define permissions (defaulting to allowed unless strictly set to false/none)
            const permissions = {
                printing: enc.permissions?.printing || 'highResolution',
                modifying: enc.permissions?.modifying !== false,
                copying: enc.permissions?.copying !== false,
                annotating: enc.permissions?.annotating !== false,
                fillingForms: enc.permissions?.fillingForms !== false,
                contentAccessibility: enc.permissions?.contentAccessibility !== false,
                documentAssembly: enc.permissions?.documentAssembly !== false
            };

            finalPdfBytes = await encryptPDF(
                finalPdfBytes,
                enc.userPassword || '',
                enc.ownerPassword || enc.userPassword || '', // Fallback to user pass if owner not set
                permissions
            );
        }

        // --- PHASE 4: UPLOAD (S3) ---
        await s3.send(new PutObjectCommand({
            Bucket: bucketName,
            Key: fileName,
            Body: finalPdfBytes,
            ContentType: 'application/pdf',
            Metadata: {
                ...(pdfLibOpts.metadata ? { //these are required
                    'title': String(pdfLibOpts.metadata.title || ''),
                    'author': String(pdfLibOpts.metadata.author || '')
                } : {})
            }
        }));

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Success',
                location: `s3://${bucketName}/${fileName}`
            }),
        };

    } catch (error) {
        console.error('Error generating PDF:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message, stack: error.stack })
        };
    } finally {
        if (browser) {
            await browser.close();
        }
    }
};