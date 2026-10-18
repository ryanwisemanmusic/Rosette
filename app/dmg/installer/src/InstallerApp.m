#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, InstallerStep) {
    InstallerStepDestination = 0,
    InstallerStepPackages = 1,
    InstallerStepSummary = 2,
    InstallerStepInstalling = 3,
    InstallerStepDone = 4,
};

@interface InstallerDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSTextField *destinationLabel;
@property(nonatomic, strong) NSTextField *destinationField;
@property(nonatomic, strong) NSButton *chooseButton;
@property(nonatomic, strong) NSScrollView *packageScroll;
@property(nonatomic, strong) NSTextField *packageStatus;
@property(nonatomic, strong) NSButton *packageRefreshButton;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *packageCatalog;
@property(nonatomic, strong) NSMutableArray<NSButton *> *packageCheckboxes;
@property(nonatomic, strong) NSTextField *summaryText;
@property(nonatomic, strong) NSTextField *statusText;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSButton *backButton;
@property(nonatomic, strong) NSButton *cancelButton;
@property(nonatomic, strong) NSButton *nextButton;
@property(nonatomic, strong) NSTimer *progressTimer;
@property(nonatomic) InstallerStep step;
@property(nonatomic) double progressTarget;
@property(nonatomic) BOOL packageCatalogLoaded;
@property(nonatomic) BOOL packageCatalogLoading;
@end

@implementation InstallerDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.packageCatalog = [NSMutableArray array];
    self.packageCheckboxes = [NSMutableArray array];
    [self buildMenuBar];
    [self buildWindow];
    [self showDestinationStep];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)buildMenuBar {
    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
    [NSApp setMainMenu:menubar];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [menubar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Rosette Installer"];
    [appItem setSubmenu:appMenu];
    [appMenu addItemWithTitle:@"Quit Rosette Installer" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 390)
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [self.window setTitle:@"Rosette Installer"];
    [self.window center];

    NSView *content = [self.window contentView];

    self.titleLabel = [self label:@"" frame:NSMakeRect(32, 320, 560, 34) fontSize:24.0 bold:YES];
    [content addSubview:self.titleLabel];

    self.subtitleLabel = [self label:@"" frame:NSMakeRect(32, 292, 560, 24) fontSize:13.0 bold:NO];
    [content addSubview:self.subtitleLabel];

    self.destinationLabel = [self label:@"Install location" frame:NSMakeRect(32, 246, 170, 20) fontSize:13.0 bold:YES];
    [content addSubview:self.destinationLabel];

    self.destinationField = [[NSTextField alloc] initWithFrame:NSMakeRect(32, 216, 420, 28)];
    [self.destinationField setStringValue:@"/Applications"];
    [content addSubview:self.destinationField];

    self.chooseButton = [[NSButton alloc] initWithFrame:NSMakeRect(466, 215, 92, 30)];
    [self.chooseButton setTitle:@"Choose..."];
    [self.chooseButton setBezelStyle:NSBezelStyleRounded];
    [self.chooseButton setTarget:self];
    [self.chooseButton setAction:@selector(chooseDestination:)];
    [content addSubview:self.chooseButton];

    self.packageScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(32, 82, 534, 178)];
    [self.packageScroll setHasVerticalScroller:YES];
    [self.packageScroll setBorderType:NSBezelBorder];
    [self.packageScroll setHidden:YES];
    [content addSubview:self.packageScroll];

    self.packageStatus = [self label:@"Loading optional package catalog..." frame:NSMakeRect(32, 266, 410, 22) fontSize:12.0 bold:NO];
    [self.packageStatus setHidden:YES];
    [content addSubview:self.packageStatus];

    self.packageRefreshButton = [[NSButton alloc] initWithFrame:NSMakeRect(450, 262, 116, 28)];
    [self.packageRefreshButton setTitle:@"Refresh List"];
    [self.packageRefreshButton setBezelStyle:NSBezelStyleRounded];
    [self.packageRefreshButton setTarget:self];
    [self.packageRefreshButton setAction:@selector(refreshPackageCatalog:)];
    [self.packageRefreshButton setHidden:YES];
    [content addSubview:self.packageRefreshButton];

    self.summaryText = [self label:@"" frame:NSMakeRect(32, 112, 534, 150) fontSize:13.0 bold:NO];
    [self.summaryText setLineBreakMode:NSLineBreakByWordWrapping];
    [self.summaryText setSelectable:YES];
    [content addSubview:self.summaryText];

    self.statusText = [self label:@"" frame:NSMakeRect(32, 160, 534, 78) fontSize:13.0 bold:NO];
    [self.statusText setLineBreakMode:NSLineBreakByWordWrapping];
    [content addSubview:self.statusText];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(32, 132, 534, 18)];
    [self.progress setIndeterminate:NO];
    [self.progress setMinValue:0.0];
    [self.progress setMaxValue:100.0];
    [self.progress setDoubleValue:0.0];
    [content addSubview:self.progress];

    self.backButton = [[NSButton alloc] initWithFrame:NSMakeRect(292, 24, 96, 32)];
    [self.backButton setTitle:@"Back"];
    [self.backButton setBezelStyle:NSBezelStyleRounded];
    [self.backButton setTarget:self];
    [self.backButton setAction:@selector(goBack:)];
    [content addSubview:self.backButton];

    self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(400, 24, 96, 32)];
    [self.cancelButton setTitle:@"Cancel"];
    [self.cancelButton setBezelStyle:NSBezelStyleRounded];
    [self.cancelButton setTarget:NSApp];
    [self.cancelButton setAction:@selector(terminate:)];
    [content addSubview:self.cancelButton];

    self.nextButton = [[NSButton alloc] initWithFrame:NSMakeRect(508, 24, 96, 32)];
    [self.nextButton setTitle:@"Next"];
    [self.nextButton setBezelStyle:NSBezelStyleRounded];
    [self.nextButton setKeyEquivalent:@"\r"];
    [self.nextButton setTarget:self];
    [self.nextButton setAction:@selector(goNext:)];
    [content addSubview:self.nextButton];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame fontSize:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    [field setStringValue:text];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setFont:bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]];
    return field;
}

- (void)showDestinationStep {
    self.step = InstallerStepDestination;
    [self.titleLabel setStringValue:@"Install Rosette"];
    [self.subtitleLabel setStringValue:@"Choose where Rosette.app should be installed."];
    [self.summaryText setHidden:YES];
    [self.statusText setHidden:YES];
    [self.progress setHidden:YES];
    [self.destinationLabel setHidden:NO];
    [self.destinationField setHidden:NO];
    [self.destinationField setEnabled:YES];
    [self.chooseButton setHidden:NO];
    [self.chooseButton setEnabled:YES];
    [self.packageScroll setHidden:YES];
    [self.packageStatus setHidden:YES];
    [self.packageRefreshButton setHidden:YES];
    [self.backButton setHidden:YES];
    [self.cancelButton setHidden:NO];
    [self.nextButton setHidden:NO];
    [self.nextButton setEnabled:YES];
    [self.nextButton setTitle:@"Next"];
    [self.nextButton setAction:@selector(goNext:)];
}

- (void)showPackagesStep {
    self.step = InstallerStepPackages;
    [self.titleLabel setStringValue:@"Optional Packages"];
    [self.subtitleLabel setStringValue:@"Choose any published Rosette packages to install alongside the core app."];
    [self.summaryText setHidden:YES];
    [self.statusText setHidden:YES];
    [self.progress setHidden:YES];
    [self.destinationLabel setHidden:YES];
    [self.destinationField setHidden:YES];
    [self.chooseButton setHidden:YES];
    [self.packageScroll setHidden:NO];
    [self.packageStatus setHidden:NO];
    [self.packageRefreshButton setHidden:NO];
    [self.packageRefreshButton setEnabled:!self.packageCatalogLoading];
    [self.backButton setHidden:NO];
    [self.backButton setEnabled:YES];
    [self.cancelButton setHidden:NO];
    [self.nextButton setHidden:NO];
    [self.nextButton setEnabled:YES];
    [self.nextButton setTitle:@"Next"];
    [self.nextButton setAction:@selector(goNext:)];

    if (!self.packageCatalogLoaded && !self.packageCatalogLoading) {
        [self loadPackageCatalog];
    }
}

- (void)showSummaryStep {
    self.step = InstallerStepSummary;
    NSString *destination = [self destinationDirectory];
    NSString *target = [destination stringByAppendingPathComponent:@"Rosette.app"];
    unsigned long long required = [self directorySizeAtPath:[self payloadPath]];
    unsigned long long available = [self availableBytesAtPath:destination];
    NSString *authLine = [self shouldUseAuthorizationForDestination:destination]
        ? @"macOS will ask for an administrator password before files are copied."
        : @"This location appears writable, so administrator authorization may not be needed.";
    NSArray<NSString *> *selectedPackages = [self selectedPackageIDs];
    NSString *packageLine = selectedPackages.count > 0
        ? [NSString stringWithFormat:@"Optional packages: %@", [selectedPackages componentsJoinedByString:@", "]]
        : @"Optional packages: none selected (the core app installs by itself).";

    [self.titleLabel setStringValue:@"Installation Summary"];
    [self.subtitleLabel setStringValue:@"Rosette is ready to install."];
    [self.summaryText setStringValue:[NSString stringWithFormat:
        @"Rosette will be installed at:\n%@\n\nSpace required: %@\nAvailable space: %@\n\n%@\n%@\n\nThe installer will also enable Rosette's global shell integration: the rosette command, make-time x86-64 ELF handling, direct ./program launches, automatic assignment result summaries, and traced Rosetta 2 fallback routing.",
        target,
        [self formatBytes:required],
        available == 0 ? @"Unknown" : [self formatBytes:available],
        authLine,
        packageLine]];
    [self.summaryText setHidden:NO];
    [self.statusText setHidden:YES];
    [self.progress setHidden:YES];
    [self.destinationLabel setHidden:YES];
    [self.destinationField setHidden:YES];
    [self.chooseButton setHidden:YES];
    [self.packageScroll setHidden:YES];
    [self.packageStatus setHidden:YES];
    [self.packageRefreshButton setHidden:YES];
    [self.backButton setHidden:NO];
    [self.backButton setEnabled:YES];
    [self.cancelButton setHidden:NO];
    [self.nextButton setHidden:NO];
    [self.nextButton setEnabled:YES];
    [self.nextButton setTitle:@"Install"];
    [self.nextButton setAction:@selector(beginInstall:)];
}

- (void)showInstallingStep {
    self.step = InstallerStepInstalling;
    [self.titleLabel setStringValue:@"Installing Rosette"];
    [self.subtitleLabel setStringValue:@"Please wait while Rosette.app and the global shell are installed."];
    [self.statusText setStringValue:@"Preparing Rosette.app, shell helpers, assignment result support, and compatibility routing..."];
    [self.statusText setHidden:NO];
    [self.summaryText setHidden:YES];
    [self.destinationLabel setHidden:YES];
    [self.destinationField setHidden:YES];
    [self.chooseButton setHidden:YES];
    [self.packageScroll setHidden:YES];
    [self.packageStatus setHidden:YES];
    [self.packageRefreshButton setHidden:YES];
    [self.progress setDoubleValue:0.0];
    [self.progress setHidden:NO];
    [self.backButton setHidden:YES];
    [self.cancelButton setHidden:NO];
    [self.cancelButton setEnabled:NO];
    [self.nextButton setHidden:YES];
}

- (void)showDoneStepWithMessage:(NSString *)message {
    self.step = InstallerStepDone;
    [self.progressTimer invalidate];
    self.progressTimer = nil;
    [self.progress setDoubleValue:100.0];
    [self.titleLabel setStringValue:@"Installation Successful"];
    [self.subtitleLabel setStringValue:@"Rosette has been installed."];
    [self.statusText setStringValue:message.length > 0 ? message : @"Rosette is ready to use from Finder's Open With menu."];
    [self.statusText setHidden:NO];
    [self.summaryText setHidden:YES];
    [self.packageScroll setHidden:YES];
    [self.packageStatus setHidden:YES];
    [self.packageRefreshButton setHidden:YES];
    [self.progress setHidden:NO];
    [self.backButton setHidden:YES];
    [self.cancelButton setHidden:YES];
    [self.nextButton setHidden:NO];
    [self.nextButton setEnabled:YES];
    [self.nextButton setTitle:@"Done"];
    [self.nextButton setAction:@selector(closeInstaller:)];
}

- (void)showError:(NSString *)message {
    [self.progressTimer invalidate];
    self.progressTimer = nil;
    [self.progress setHidden:YES];
    [self.packageScroll setHidden:YES];
    [self.packageStatus setHidden:YES];
    [self.packageRefreshButton setHidden:YES];
    [self.statusText setHidden:NO];
    [self.statusText setStringValue:message.length > 0 ? message : @"Installation failed."];
    [self.titleLabel setStringValue:@"Installation Failed"];
    [self.subtitleLabel setStringValue:@"Rosette could not be installed."];
    [self.backButton setHidden:NO];
    [self.backButton setEnabled:YES];
    [self.cancelButton setHidden:NO];
    [self.cancelButton setEnabled:YES];
    [self.nextButton setHidden:YES];
}

- (void)chooseDestination:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [self.destinationField setStringValue:[[panel URL] path]];
        }
    }];
}

- (void)refreshPackageCatalog:(id)sender {
    (void)sender;
    self.packageCatalogLoaded = NO;
    [self.packageCatalog removeAllObjects];
    [self rebuildPackageCheckboxes];
    [self loadPackageCatalog];
}

- (NSURL *)packageIndexURL {
    NSString *payload = [self payloadPath];
    NSString *indexPath = [payload stringByAppendingPathComponent:
        @"Contents/Resources/rosette-runtime/pkg/registry/package-index-url.txt"];
    NSString *configured = [NSString stringWithContentsOfFile:indexPath
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil];
    NSString *value = [configured stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = value.length > 0 ? [NSURL URLWithString:value] : nil;
    if (url == nil || url.host.length == 0) return nil;
    return [[url scheme] caseInsensitiveCompare:@"https"] == NSOrderedSame ? url : nil;
}

- (void)loadPackageCatalog {
    if (self.packageCatalogLoading) return;
    NSURL *url = [self packageIndexURL];
    if (url == nil) {
        self.packageCatalogLoaded = YES;
        [self.packageStatus setStringValue:@"No valid HTTPS package catalog is configured. The core install is ready."];
        [self rebuildPackageCheckboxes];
        return;
    }

    self.packageCatalogLoading = YES;
    [self.packageRefreshButton setEnabled:NO];
    [self.packageStatus setStringValue:@"Checking the Rosette release catalog..."];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:20.0];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
            NSString *message = nil;
            if (error != nil) {
                message = [NSString stringWithFormat:
                    @"Could not load optional packages (%@). The core install is still available; use Refresh List to retry.",
                    error.localizedDescription];
            } else if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
                message = @"The package catalog returned an invalid response. The core install is still available.";
            } else if ([response URL].host.length == 0 ||
                       [[[response URL] scheme] caseInsensitiveCompare:@"https"] != NSOrderedSame) {
                message = @"The package catalog redirected to a non-HTTPS address and was rejected.";
            } else {
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                if (status == 404) {
                    message = @"No optional packages have been published yet. The core Rosette install is ready.";
                } else if (status != 200) {
                    message = [NSString stringWithFormat:
                        @"The package catalog returned HTTP %ld. The core install is still available; use Refresh List to retry.",
                        (long)status];
                } else if (data.length > 1024 * 1024) {
                    message = @"The package catalog is larger than 1 MiB and was rejected.";
                } else {
                    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (text == nil) {
                        message = @"The package catalog is not UTF-8 text. The core install is still available.";
                    } else {
                        NSMutableSet<NSString *> *seen = [NSMutableSet set];
                        NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
                        NSPredicate *idPattern = [NSPredicate predicateWithFormat:
                            @"SELF MATCHES %@", @"[a-z0-9][a-z0-9._-]{0,127}"];
                        NSPredicate *versionPattern = [NSPredicate predicateWithFormat:
                            @"SELF MATCHES %@", @"[A-Za-z0-9][A-Za-z0-9._-]{0,127}"];
                        for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
                            NSString *line = [rawLine stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                            if (line.length == 0 || [line hasPrefix:@"#"]) continue;
                            NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
                            if (fields.count != 5 || ![idPattern evaluateWithObject:fields[0]] ||
                                ![versionPattern evaluateWithObject:fields[1]] ||
                                fields[2].length != 64 || [fields[2] rangeOfCharacterFromSet:
                                    [hex invertedSet]].location != NSNotFound ||
                                fields[3].length == 0) {
                                message = @"The package catalog contains a malformed row and was rejected.";
                                [rows removeAllObjects];
                                break;
                            }
                            NSURL *assetURL = [NSURL URLWithString:fields[3]];
                            if (assetURL == nil || assetURL.host.length == 0 ||
                                [[assetURL scheme] caseInsensitiveCompare:@"https"] != NSOrderedSame ||
                                [seen containsObject:fields[0]]) {
                                message = @"The package catalog contains a duplicate ID or non-HTTPS asset and was rejected.";
                                [rows removeAllObjects];
                                break;
                            }
                            [seen addObject:fields[0]];
                            [rows addObject:@{
                                @"id": fields[0],
                                @"version": fields[1],
                                @"sha256": fields[2],
                                @"url": fields[3],
                                @"description": fields[4].length > 0 ? fields[4] : fields[0],
                            }];
                            if (rows.count > 200) {
                                message = @"The package catalog exceeds the 200 package limit and was rejected.";
                                [rows removeAllObjects];
                                break;
                            }
                        }
                        if (message == nil) {
                            message = rows.count > 0
                                ? @"Select optional packages to install. Checksums are verified before extraction."
                                : @"No optional packages have been published yet. The core Rosette install is ready.";
                        }
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.packageCatalog removeAllObjects];
                [self.packageCatalog addObjectsFromArray:rows];
                self.packageCatalogLoading = NO;
                self.packageCatalogLoaded = YES;
                [self.packageRefreshButton setEnabled:YES];
                [self.packageStatus setStringValue:message ?: @"The core Rosette install is ready."];
                [self rebuildPackageCheckboxes];
            });
        }];
    [task resume];
}

- (void)rebuildPackageCheckboxes {
    [self.packageCheckboxes removeAllObjects];
    CGFloat rowHeight = 34.0;
    CGFloat contentHeight = MAX(rowHeight, self.packageCatalog.count * rowHeight);
    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 510, contentHeight)];
    for (NSUInteger index = 0; index < self.packageCatalog.count; index++) {
        NSDictionary *package = self.packageCatalog[index];
        CGFloat y = contentHeight - ((index + 1) * rowHeight);
        NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(8, y, 486, 28)];
        [checkbox setButtonType:NSButtonTypeSwitch];
        [checkbox setTitle:[NSString stringWithFormat:@"%@ %@ — %@",
            package[@"id"], package[@"version"], package[@"description"]]];
        [checkbox setState:NSControlStateValueOff];
        [document addSubview:checkbox];
        [self.packageCheckboxes addObject:checkbox];
    }
    [self.packageScroll setDocumentView:document];
}

- (NSArray<NSString *> *)selectedPackageIDs {
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.packageCheckboxes.count && index < self.packageCatalog.count; index++) {
        if ([self.packageCheckboxes[index] state] == NSControlStateValueOn) {
            [selected addObject:self.packageCatalog[index][@"id"]];
        }
    }
    return selected;
}

- (NSArray<NSString *> *)selectedPackageSpecs {
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.packageCheckboxes.count && index < self.packageCatalog.count; index++) {
        if ([self.packageCheckboxes[index] state] == NSControlStateValueOn) {
            NSDictionary *package = self.packageCatalog[index];
            [selected addObject:[NSString stringWithFormat:@"%@:%@:%@",
                package[@"id"], package[@"version"], package[@"sha256"]]];
        }
    }
    return selected;
}

- (void)goNext:(id)sender {
    (void)sender;
    if (self.step == InstallerStepDestination) {
        [self showPackagesStep];
    } else if (self.step == InstallerStepPackages) {
        [self showSummaryStep];
    }
}

- (void)goBack:(id)sender {
    (void)sender;
    if (self.step == InstallerStepPackages) {
        [self showDestinationStep];
    } else if (self.step == InstallerStepSummary) {
        [self showPackagesStep];
    } else {
        [self showSummaryStep];
    }
}

- (void)beginInstall:(id)sender {
    (void)sender;
    NSString *payload = [self payloadPath];
    NSString *helper = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"rosette-install-helper"];
    NSString *destination = [self destinationDirectory];

    if (payload.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:payload]) {
        [self showError:@"Rosette.app payload is missing from installer resources."];
        return;
    }
    if (helper.length == 0) {
        [self showError:@"The installer helper is missing from this bundle."];
        return;
    }
    if (destination.length == 0) {
        [self showError:@"Choose an install location."];
        return;
    }

    [self showInstallingStep];

    if ([self shouldUseAuthorizationForDestination:destination]) {
        [self.statusText setStringValue:@"Waiting for administrator authorization..."];
        [self runAuthorizedInstallWithHelper:helper payload:payload destination:destination];
    } else {
        [self.statusText setStringValue:@"Copying Rosette.app..."];
        [self startProgressTimer];
        [self runDirectInstallWithHelper:helper payload:payload destination:destination];
    }
}

- (void)runDirectInstallWithHelper:(NSString *)helper payload:(NSString *)payload destination:(NSString *)destination {
    NSArray<NSString *> *packageSpecs = [self selectedPackageSpecs];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setExecutableURL:[NSURL fileURLWithPath:helper]];
        [task setArguments:[[ @[ @"--install", payload, destination ] arrayByAddingObjectsFromArray:packageSpecs ] copy]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        NSError *error = nil;
        BOOL launched = [task launchAndReturnError:&error];
        if (!launched) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:[NSString stringWithFormat:@"Could not start installer helper: %@", [error localizedDescription]]];
            });
            return;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        int status = [task terminationStatus];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == 0) {
                [self showDoneStepWithMessage:[self doneMessageForDestination:destination output:output]];
            } else {
                [self showError:[NSString stringWithFormat:@"Installer helper exited with status %d.\n%@", status, output ?: @""]];
            }
        });
    });
}

- (void)runAuthorizedInstallWithHelper:(NSString *)helper payload:(NSString *)payload destination:(NSString *)destination {
    NSString *marker = [NSString stringWithFormat:@"/private/tmp/rosette-installer-auth-%@.marker", [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];
    [self startAuthorizationPollForMarker:marker];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *command = [NSString stringWithFormat:@"/bin/echo authorized > %@ && %@ --copy %@ %@ 2>&1",
                             [self shellQuoted:marker],
                             [self shellQuoted:helper],
                             [self shellQuoted:payload],
                             [self shellQuoted:destination]];
        NSString *source = [NSString stringWithFormat:@"do shell script %@ with administrator privileges",
                            [self appleScriptQuoted:command]];
        NSTask *task = [[NSTask alloc] init];
        [task setExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/osascript"]];
        [task setArguments:@[ @"-e", source ]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        NSError *error = nil;
        BOOL launched = [task launchAndReturnError:&error];
        if (!launched) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:[NSString stringWithFormat:@"Could not start authorization prompt: %@", [error localizedDescription]]];
            });
            return;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        int status = [task terminationStatus];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];
            if (status == 0) {
                [self.statusText setStringValue:@"Copy complete. Registering Rosette and installing per-user shell integration..."];
                [self runDirectConfigureWithHelper:helper destination:destination copyOutput:output packageSpecs:[self selectedPackageSpecs]];
            } else {
                [self showError:output.length > 0 ? output : @"Administrator authorization was cancelled or failed."];
            }
        });
    });
}

- (void)runDirectConfigureWithHelper:(NSString *)helper destination:(NSString *)destination copyOutput:(NSString *)copyOutput packageSpecs:(NSArray<NSString *> *)packageSpecs {
    NSString *target = [destination stringByAppendingPathComponent:@"Rosette.app"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setExecutableURL:[NSURL fileURLWithPath:helper]];
        [task setArguments:[[ @[ @"--configure", target ] arrayByAddingObjectsFromArray:packageSpecs ] copy]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        NSError *error = nil;
        if (![task launchAndReturnError:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:[NSString stringWithFormat:@"Rosette was copied, but setup could not start: %@", error.localizedDescription]];
            });
            return;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        int status = [task terminationStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == 0) {
                NSString *combined = copyOutput.length > 0 && output.length > 0
                    ? [NSString stringWithFormat:@"%@\n%@", copyOutput, output]
                    : (copyOutput.length > 0 ? copyOutput : output);
                [self showDoneStepWithMessage:[self doneMessageForDestination:destination output:combined]];
            } else {
                [self showError:[NSString stringWithFormat:@"Rosette was copied, but setup failed with status %d.\n%@", status, output ?: @""]];
            }
        });
    });
}

- (void)startAuthorizationPollForMarker:(NSString *)marker {
    [self.progressTimer invalidate];
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.12
                                                          repeats:YES
                                                            block:^(NSTimer *timer) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:marker]) {
            [timer invalidate];
            [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];
            [self.progress setDoubleValue:5.0];
            [self.statusText setStringValue:@"Authorization accepted. Copying Rosette.app and preparing global shell integration..."];
            [self startProgressTimer];
        }
    }];
}

- (void)startProgressTimer {
    [self.progressTimer invalidate];
    self.progressTarget = 88.0;
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.06
                                                          target:self
                                                        selector:@selector(tickProgress:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)tickProgress:(NSTimer *)timer {
    (void)timer;
    double value = [self.progress doubleValue];
    if (value < self.progressTarget) {
        [self.progress setDoubleValue:value + 1.0];
        [self updateInstallingStatusForProgress:value + 1.0];
    }
}

- (void)updateInstallingStatusForProgress:(double)value {
    if (self.step != InstallerStepInstalling) {
        return;
    }
    NSString *message = nil;
    if (value < 18.0) {
        message = @"Verifying Rosette.app payload helpers...";
    } else if (value < 34.0) {
        message = @"Copying Rosette.app to the selected destination...";
    } else if (value < 50.0) {
        message = @"Registering Finder Open With support for Rosette...";
    } else if (value < 66.0) {
        message = @"Installing global shell commands and cleanup backend...";
    } else if (value < 80.0) {
        message = @"Installing elf_processor, macho_processor, rosette-router, and assembler helpers...";
    } else {
        message = @"Writing ~/.rosette/config.toml with automatic assignment result summaries...";
    }
    if (![[self.statusText stringValue] isEqualToString:message]) {
        [self.statusText setStringValue:message];
    }
}

- (NSString *)destinationDirectory {
    NSString *value = [[self.destinationField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value.length > 0 ? value : @"/Applications";
}

- (NSString *)payloadPath {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Rosette.app"];
}

- (BOOL)shouldUseAuthorizationForDestination:(NSString *)destination {
    if ([destination isEqualToString:@"/Applications"]) {
        return YES;
    }
    return ![[NSFileManager defaultManager] isWritableFileAtPath:destination];
}

- (unsigned long long)directorySizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    unsigned long long total = 0;
    NSString *entry = nil;
    while ((entry = [enumerator nextObject]) != nil) {
        NSString *fullPath = [path stringByAppendingPathComponent:entry];
        NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

- (unsigned long long)availableBytesAtPath:(NSString *)path {
    NSDictionary<NSFileAttributeKey, id> *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:path error:nil];
    return [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
}

- (NSString *)formatBytes:(unsigned long long)bytes {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    [formatter setCountStyle:NSByteCountFormatterCountStyleFile];
    return [formatter stringFromByteCount:(long long)bytes];
}

- (NSString *)doneMessageForDestination:(NSString *)destination output:(NSString *)output {
    NSString *target = [destination stringByAppendingPathComponent:@"Rosette.app"];
    NSString *base = [NSString stringWithFormat:@"Rosette was installed at:\n%@\n\nFinder can use Rosette through Open With for supported .exe and .com files.\n\nThe global shell is installed too. In supported x86-64 assembly assignment folders, run make run or ./program to see Rosette's normalized result summary.\n\nCompatibility routing is installed as rosette route, with traced x86_64 Mach-O diagnostics and Apple Rosetta 2 fallback for Intel macOS apps.", target];
    if (output.length == 0) {
        return base;
    }
    return [NSString stringWithFormat:@"%@\n\n%@", base, output];
}

- (NSString *)shellQuoted:(NSString *)value {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (NSString *)appleScriptQuoted:(NSString *)value {
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, [escaped length])];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

- (void)closeInstaller:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        InstallerDelegate *delegate = [[InstallerDelegate alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
