#import <Cocoa/Cocoa.h>

@interface UninstallerDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *appPathField;
@property(nonatomic, strong) NSTextView *logView;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSButton *removeButton;
@end

@implementation UninstallerDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self buildMenuBar];
    [self buildWindow];
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
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Rosette Uninstaller"];
    [appItem setSubmenu:appMenu];
    [appMenu addItemWithTitle:@"Quit Rosette Uninstaller" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 390)
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [self.window setTitle:@"Rosette Uninstaller"];
    [self.window center];

    NSView *content = [self.window contentView];

    [content addSubview:[self label:@"Remove Rosette" frame:NSMakeRect(28, 330, 560, 28) fontSize:22.0 bold:YES]];
    [content addSubview:[self label:@"Choose the installed Rosette.app bundle to remove." frame:NSMakeRect(28, 300, 560, 22) fontSize:13.0 bold:NO]];
    [content addSubview:[self label:@"Application bundle" frame:NSMakeRect(28, 260, 160, 20) fontSize:13.0 bold:YES]];

    self.appPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 230, 430, 28)];
    [self.appPathField setStringValue:@"/Applications/Rosette.app"];
    [content addSubview:self.appPathField];

    NSButton *chooseButton = [[NSButton alloc] initWithFrame:NSMakeRect(470, 229, 92, 30)];
    [chooseButton setTitle:@"Choose..."];
    [chooseButton setBezelStyle:NSBezelStyleRounded];
    [chooseButton setTarget:self];
    [chooseButton setAction:@selector(chooseApplication:)];
    [content addSubview:chooseButton];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(28, 195, 534, 18)];
    [self.progress setIndeterminate:YES];
    [self.progress setDisplayedWhenStopped:NO];
    [content addSubview:self.progress];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 62, 534, 120)];
    [scroll setHasVerticalScroller:YES];
    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 534, 120)];
    [self.logView setEditable:NO];
    [self.logView setFont:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular]];
    [scroll setDocumentView:self.logView];
    [content addSubview:scroll];

    self.removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(452, 20, 110, 32)];
    [self.removeButton setTitle:@"Remove"];
    [self.removeButton setBezelStyle:NSBezelStyleRounded];
    [self.removeButton setKeyEquivalent:@"\r"];
    [self.removeButton setTarget:self];
    [self.removeButton setAction:@selector(runRemove:)];
    [content addSubview:self.removeButton];

    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(340, 20, 100, 32)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setBezelStyle:NSBezelStyleRounded];
    [cancelButton setTarget:NSApp];
    [cancelButton setAction:@selector(terminate:)];
    [content addSubview:cancelButton];

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

- (void)chooseApplication:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [self.appPathField setStringValue:[[panel URL] path]];
        }
    }];
}

- (void)runRemove:(id)sender {
    (void)sender;
    NSString *helper = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"rosette-uninstall-helper"];
    NSString *target = [self.appPathField stringValue];
    if (helper.length == 0) {
        [self appendLine:@"error: uninstaller helper is missing"];
        return;
    }
    if (target.length == 0) {
        [self appendLine:@"error: choose a Rosette.app bundle"];
        return;
    }

    [self.removeButton setEnabled:NO];
    [self.progress startAnimation:nil];
    [self appendLine:@"Starting removal..."];
    if ([self shouldUseAuthorizationForTarget:target]) {
        [self appendLine:@"Waiting for administrator authorization..."];
        [self runAuthorizedRemoveWithHelper:helper target:target];
    } else {
        [self runHelper:helper arguments:@[ @"--remove", target ] completionTitle:@"Done"];
    }
}

- (BOOL)shouldUseAuthorizationForTarget:(NSString *)target {
    // /Applications is normally owned by root.  Checking its parent also
    // handles a bundle selected in another protected location.
    NSString *parent = [target stringByDeletingLastPathComponent];
    return [target hasPrefix:@"/Applications/"] ||
        ![[NSFileManager defaultManager] isWritableFileAtPath:parent];
}

- (void)runAuthorizedRemoveWithHelper:(NSString *)helper target:(NSString *)target {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *command = [NSString stringWithFormat:@"%@ --remove %@ 2>&1",
                             [self shellQuoted:helper], [self shellQuoted:target]];
        NSString *source = [NSString stringWithFormat:@"do shell script %@ with administrator privileges",
                            [self appleScriptQuoted:command]];
        NSTask *task = [[NSTask alloc] init];
        [task setExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/osascript"]];
        [task setArguments:@[ @"-e", source ]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        NSError *error = nil;
        if (![task launchAndReturnError:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.progress stopAnimation:nil];
                [self.removeButton setEnabled:YES];
                [self appendLine:[NSString stringWithFormat:@"error: could not start authorization prompt: %@", error.localizedDescription]];
            });
            return;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        int status = [task terminationStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progress stopAnimation:nil];
            [self appendLine:output.length > 0 ? output : @"helper completed"];
            if (status == 0) {
                [self.removeButton setTitle:@"Done"];
                [self.removeButton setAction:@selector(closeUninstaller:)];
            } else {
                [self appendLine:@"error: administrator authorization was cancelled or removal failed"];
            }
            [self.removeButton setEnabled:YES];
        });
    });
}

- (void)runHelper:(NSString *)helper arguments:(NSArray<NSString *> *)arguments completionTitle:(NSString *)completionTitle {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setExecutableURL:[NSURL fileURLWithPath:helper]];
        [task setArguments:arguments];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];

        NSError *error = nil;
        BOOL launched = [task launchAndReturnError:&error];
        if (!launched) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.progress stopAnimation:nil];
                [self.removeButton setEnabled:YES];
                [self appendLine:[NSString stringWithFormat:@"error: %@", [error localizedDescription]]];
            });
            return;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        int status = [task terminationStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progress stopAnimation:nil];
            [self appendLine:output.length > 0 ? output : @"helper completed"];
            if (status == 0) {
                [self.removeButton setTitle:completionTitle];
                [self.removeButton setAction:@selector(closeUninstaller:)];
                [self.removeButton setEnabled:YES];
            } else {
                [self.removeButton setEnabled:YES];
                [self appendLine:[NSString stringWithFormat:@"error: helper exited with status %d", status]];
            }
        });
    });
}

- (void)closeUninstaller:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)appendLine:(NSString *)line {
    if (line.length == 0) {
        return;
    }
    NSString *text = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    [[self.logView textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
    [self.logView scrollRangeToVisible:NSMakeRange([[self.logView string] length], 0)];
}

- (NSString *)shellQuoted:(NSString *)value {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (NSString *)appleScriptQuoted:(NSString *)value {
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        UninstallerDelegate *delegate = [[UninstallerDelegate alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
