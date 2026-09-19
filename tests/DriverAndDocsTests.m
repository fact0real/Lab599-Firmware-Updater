#import <Foundation/Foundation.h>
#import "../Headers/Lab599DriverController.h"
#import "../Headers/Lab599DocsController.h"
#import "../Headers/Lab599FirmwareCatalog.h"

static void Check(BOOL ok, NSString *label) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", label.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        printf("Running Driver and Documentation tests...\n");

        // 1. Driver Controller Tests
        Lab599DriverController *driverCtrl = [Lab599DriverController new];
        Check(driverCtrl != nil, @"Driver controller instantiates");
        Check(driverCtrl.view != nil, @"Driver controller view exists");
        [driverCtrl checkDriverStatus];
        [driverCtrl refreshDevices];
        NSImage *radioImg = [driverCtrl loadRadioImage];
        Check(radioImg != nil, @"TX-500 radio image loads successfully");
        Check(radioImg.size.width > 0 && radioImg.size.height > 0, @"TX-500 radio image has valid dimensions");

        NSImage *mpImg = [[NSImage alloc] initWithContentsOfFile:@"Resources/tx500_mp.png"];
        Check(mpImg != nil, @"TX-500MP radio image loads successfully");
        Check(mpImg.size.width > 0 && mpImg.size.height > 0, @"TX-500MP radio image has valid dimensions");

        NSImage *proImg = [[NSImage alloc] initWithContentsOfFile:@"Resources/tx500_pro.png"];
        Check(proImg != nil, @"TX-500PRO radio image loads successfully");
        Check(proImg.size.width > 0 && proImg.size.height > 0, @"TX-500PRO radio image has valid dimensions");

        NSImage *altaiImg = [[NSImage alloc] initWithContentsOfFile:@"Resources/tx500_pro_altai.png"];
        Check(altaiImg != nil, @"TX-500PRO ALTAI radio image loads successfully");
        Check(altaiImg.size.width > 0 && altaiImg.size.height > 0, @"TX-500PRO ALTAI radio image has valid dimensions");
        printf("PASS: All 4 radio hardware models verified (Discovery: %.0fx%.0f, MP: %.0fx%.0f, PRO: %.0fx%.0f, ALTAI: %.0fx%.0f)\n",
               radioImg.size.width, radioImg.size.height,
               mpImg.size.width, mpImg.size.height,
               proImg.size.width, proImg.size.height,
               altaiImg.size.width, altaiImg.size.height);

        // 2. Documentation Controller Tests
        Lab599DocsController *docsCtrl = [Lab599DocsController new];
        Check(docsCtrl != nil, @"Docs controller instantiates");
        Check(docsCtrl.view != nil, @"Docs controller view exists");

        // Check fallback catalog
        NSArray<Lab599DocItem *> *fallback = [docsCtrl builtInDocumentationCatalog];
        Check(fallback.count >= 50, @"Built-in docs catalog contains all known items");

        BOOL foundManual = NO, foundFW = NO, foundTool = NO, foundDriver = NO;
        BOOL foundPRO = NO, foundRU = NO;
        for (Lab599DocItem *it in fallback) {
            Check(it.title.length > 0, @"Item title is non-empty");
            Check(it.downloadURL != nil, @"Item download URL exists");
            Check([it.downloadURL.scheme isEqualToString:@"https"], @"Item URL is HTTPS");
            if ([it.category isEqualToString:@"Manuals & Guides"]) foundManual = YES;
            if ([it.category isEqualToString:@"Firmware"]) foundFW = YES;
            if ([it.category isEqualToString:@"Software & Tools"]) foundTool = YES;
            if ([it.category isEqualToString:@"Drivers"]) foundDriver = YES;
            if ([it.title containsString:@"TX-500PRO"]) foundPRO = YES;
            if ([it.title containsString:@"Russian"]) foundRU = YES;
        }
        Check(foundManual && foundFW && foundTool && foundDriver, @"All categories present in documentation catalog");
        Check(foundPRO, @"TX-500PRO items present in catalog");
        Check(foundRU, @"Russian localized items present in catalog");
        printf("PASS: Documentation fallback catalog verified (%lu items across 4 categories, includes PRO and RU)\n", (unsigned long)fallback.count);

        // Test HTML Parser with international and RU content
        NSString *sampleHTML =
            @"<div>"
            @"<a href=\"https://downloads.lab599.com/TX500/Lab599-TX500-User-Manual-EN-FW-v1.2.pdf\">3.3 MB</a>"
            @"<a href=\"https://downloads.lab599.com/TX500/mtrx1.30.00.fw\">240 Kb</a>"
            @"<a href=\"https://downloads.lab599.com/SW/Lab599-TRX-TestCAT-1.1-EN.zip\">263 Kb</a>"
            @"<a href=\"https://downloads.lab599.com/TX500/FTDI_FT232_v2.12.28.zip\">1.8 MB</a>"
            @"<a href=\"https://downloads.lab599.ru/TX500PRO/mtrx_pro1.29.05.fw\">245 Кб</a>"
            @"<a href=\"https://downloads.lab599.ru/TX500/TX500-Changelog-RU.txt\">15 Кб</a>"
            @"</div>";
        NSArray<Lab599DocItem *> *parsed = [docsCtrl parseItemsFromHTML:sampleHTML];
        Check(parsed.count == 6, @"HTML parsing extracts correct number of download links");
        Check([parsed[0].fileFormat isEqualToString:@"PDF"], @"PDF format recognized");
        Check([parsed[1].fileFormat isEqualToString:@"FW"], @"FW format recognized");
        Check([parsed[2].fileFormat isEqualToString:@"ZIP"], @"ZIP format recognized");
        Check([parsed[4].fileFormat isEqualToString:@"FW"], @"RU FW format recognized");
        Check([parsed[5].fileFormat isEqualToString:@"TXT"], @"RU TXT format recognized");
        printf("PASS: Documentation live HTML parser verified with com and ru formats\n");

        // 3. Firmware Catalog Model Tests
        NSArray<Lab599FirmwareItem *> *fwCatalog = [Lab599FirmwareCatalog fallbackFirmwareCatalog];
        BOOL foundDiscFW = NO, foundMPFW = NO, foundProFW = NO, foundAltaiFW = NO;
        for (Lab599FirmwareItem *item in fwCatalog) {
            if ([item.model isEqualToString:@"TX-500 Discovery"]) foundDiscFW = YES;
            if ([item.model isEqualToString:@"TX-500MP"]) foundMPFW = YES;
            if ([item.model isEqualToString:@"TX-500PRO"]) foundProFW = YES;
            if ([item.model isEqualToString:@"TX-500PRO ALTAI"]) foundAltaiFW = YES;
        }
        Check(foundDiscFW, @"Fallback catalog contains TX-500 Discovery firmware");
        Check(foundMPFW, @"Fallback catalog contains TX-500MP firmware");
        Check(foundProFW, @"Fallback catalog contains TX-500PRO firmware");
        Check(foundAltaiFW, @"Fallback catalog contains TX-500PRO ALTAI firmware");
        printf("PASS: Firmware catalog verified for Discovery, MP, PRO, and PRO ALTAI models (%lu items)\n", (unsigned long)fwCatalog.count);

        printf("All Driver and Documentation tests passed.\n");
    }
    return 0;
}
