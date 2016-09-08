//
//  AppController.m
//  ScreenToLayers
//
//  Created by Jeremy Vizzini.
//  This software is released subject to licensing conditions as detailed in Licence.txt.
//

#import "AppController.h"
#import "ListController.h"
#import "ScreenGraber.h"
#import "Presentation.h"
#import "PSDWriter.h"
#import "Preferences.h"
#import "Constants.h"

#pragma mark AppController Private

@interface AppController ()

@property (weak) IBOutlet NSMenu *statusMenu;
@property (strong) NSStatusItem *statusItem;
@property (strong) ScreenGraber *graber;
@property (strong) NSSound *flashSound;
@property (strong) NSSound *timerSound;
@property (assign) NSInteger timerCount;
@property (strong) NSImage *defaultBarImage;
@property (strong) NSImage *flashBarImage;

@end

#pragma mark AppController Implementation

@implementation AppController

#pragma mark Initializers

- (instancetype)init {
    self = [super init];
    if (self) {
        self.timerCount = -1;
        self.graber = [[ScreenGraber alloc] init];
        self.graber.cursorOnTop = true;
        
        self.flashSound = [NSSound soundNamed:@"CaptureEndSound"];
        self.timerSound = [NSSound soundNamed:@"Tink"];
        self.timerSound.volume = 0.3;
        
        self.defaultBarImage = [NSImage imageNamed:@"ToolbarTemplate"];
        self.flashBarImage = [NSImage imageNamed:@"ToolbarFlashTemplate"];
    }
    return self;
}

#pragma mark NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [Preferences setupDefaults];
    
    [self setupStatusItem];
    [self registerHotKeys];
    
    if ([Preferences launchCount] == 1) {
        [self showPreferences:nil];
        [self showPresentation:nil];
    }
}

#pragma mark Hotkeys

typedef OSStatus (*GrabHotKeyHandler)(EventHandlerCallRef h,EventRef e, void *d);

static OSStatus _grabNowHotKeyHandler(EventHandlerCallRef h,EventRef e, void *d) {
    [NSApp sendAction:@selector(grabScreenshot:) to:nil from:nil];
    return noErr;
}

static OSStatus _grabDelayHotKeyHandler(EventHandlerCallRef h,EventRef e, void *d) {
    [NSApp sendAction:@selector(grabScreenshotWithDelay:) to:nil from:nil];
    return noErr;
}

static void _registerGrabHotKey(GrabHotKeyHandler handler, int ansi) {
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    InstallApplicationEventHandler(handler,
                                   1,
                                   &eventType,
                                   NULL,
                                   NULL);
    
    EventHotKeyRef gMyHotKeyRef;
    EventHotKeyID gMyHotKeyID;
    gMyHotKeyID.signature = 'rml1';
    gMyHotKeyID.id = 1;
    RegisterEventHotKey(ansi,
                        cmdKey+shiftKey,
                        gMyHotKeyID,
                        GetApplicationEventTarget(),
                        0,
                        &gMyHotKeyRef);
}

- (void)registerHotKeys {
    _registerGrabHotKey(_grabNowHotKeyHandler, kVK_ANSI_5);
    _registerGrabHotKey(_grabDelayHotKeyHandler, kVK_ANSI_6);
}

#pragma mark Status item

- (void)setupStatusItem {
    NSStatusBar *sb = [NSStatusBar systemStatusBar];
    self.statusItem = [sb statusItemWithLength:26];
    self.statusItem.image = [NSImage imageNamed:@"ToolbarTemplate"];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.highlightMode = YES;
}

- (void)updateBarWithTimer {
    self.statusItem.image = nil;
    self.statusItem.title = [NSString stringWithFormat:@"%ld", self.timerCount];
}

- (void)updateBarWithFlash {
    self.statusItem.image = [NSImage imageNamed:@"ToolbarFlashTemplate"];
    self.statusItem.title = nil;
}

- (void)restoreBarWithImage {
    self.statusItem.image = [NSImage imageNamed:@"ToolbarTemplate"];
    self.statusItem.title = nil;
}

#pragma mark Screenshot

- (NSURL *)screenshotsDirectoryURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *directoryURL = [Preferences exportDirectoryURL];
    [fm createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

- (NSString *)filenameForCurrentDate {
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH-mm-ss";
    return [dateFormatter stringFromDate:[NSDate date]];
}

- (NSURL *)psdURLForCurrentDate {
    NSURL *dirURL = [self screenshotsDirectoryURL];
    NSString *filename = [self filenameForCurrentDate];
    NSURL *fileURL = [dirURL URLByAppendingPathComponent:filename];
    return [fileURL URLByAppendingPathExtension:@"psd"];
}

- (void)saveScreenToFile {
    NSURL *fileURL = [self psdURLForCurrentDate];
    if (![self.graber saveScreenAsPSDToFileURL:fileURL]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"An error ocurred";
        [alert addButtonWithTitle:@"OK"];
        alert.informativeText = @"Couldn't grab the screen.";
        [alert runModal];
        return;
    }
    
    if ([Preferences shouldAutoOpenFolder]) {
        [[NSWorkspace sharedWorkspace] openURL:[self screenshotsDirectoryURL]];
    }
    if ([Preferences shouldAutoOpenScreenshot]) {
        [[NSWorkspace sharedWorkspace] openURL:fileURL];
    }
}

#pragma mark Actions

- (IBAction)grabScreenshot:(id)sender {
    if (self.timerCount != -1) {
        return;
    }
    
    [self updateBarWithFlash];
    if ([Preferences shouldPlayFlashSound]) {
        [self.flashSound play];
    }
    
    int queueId = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
    dispatch_async(dispatch_get_global_queue(queueId, 0), ^{
        [self saveScreenToFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self restoreBarWithImage];
        });
    });
}

- (void)updateScreenshotTimer:(NSTimer *)timer {
    if (self.timerCount != 0) {
        [self updateBarWithTimer];
        self.timerCount--;
        if ([Preferences shouldPlayTimerSound]) {
            [self.timerSound play];
        }
        return;
    }
    
    self.timerCount = -1;
    [timer invalidate];
    [self grabScreenshot: nil];
}

- (IBAction)grabScreenshotWithDelay:(id)sender {
    if (self.timerCount != -1) {
        return;
    }
    
    self.timerCount = 5;
    [self updateBarWithTimer];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(updateScreenshotTimer:)
                                   userInfo:nil
                                    repeats:YES];
}

- (IBAction)openOutputsFolder:(id)sender {
    NSURL *dirURL = [self screenshotsDirectoryURL];
    [[NSWorkspace sharedWorkspace] openURL:dirURL];
}

- (IBAction)showWindowsList:(id)sender {
    [[ListController sharedController] showWindow:sender];
}

- (IBAction)showPreferences:(id)sender {
    [[Preferences sharedInstance] showWindow:sender];
}

- (IBAction)showPresentation:(id)sender {
    [[Presentation sharedInstance] showWindow:sender];
}

- (IBAction)contactCustomerSupport:(id)sender {
    NSSharingService *service = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
    service.recipients = @[SupportAddress];
    service.subject = [NSString stringWithFormat:@"[%@] support", ApplicationName];
    [service performWithItems:@[]];
}

- (IBAction)openApplicationWebsite:(id)sender {
    NSURL *websiteURL = [NSURL URLWithString:WebsiteStringURL];
    [[NSWorkspace sharedWorkspace] openURL:websiteURL];
}

- (IBAction)openAppStorePage:(id)sender {
    NSURL *websiteURL = [NSURL URLWithString:AppStoreStringURL];
    [[NSWorkspace sharedWorkspace] openURL:websiteURL];
}

- (IBAction)openGitHubPage:(id)sender {
    NSURL *websiteURL = [NSURL URLWithString:GitHubStringURL];
    [[NSWorkspace sharedWorkspace] openURL:websiteURL];
}

@end
