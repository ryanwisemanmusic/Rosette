#import "native_window_toolbar.h"
#import "native_window_bridge.h"

#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <math.h>
#import <unistd.h>

static NSToolbarItemIdentifier const kScreenshotItem = @"rosette.screenshot";
static NSToolbarItemIdentifier const kVideoItem = @"rosette.video";
static NSToolbarItemIdentifier const kGfxrItem = @"rosette.gfxr";
static NSToolbarItemIdentifier const kFPSItem = @"rosette.fps";
static NSToolbarItemIdentifier const kBrightnessItem = @"rosette.brightness";

static void RosetteToolbarShowAlert(NSWindow *window, NSString *title,
                                    NSString *message) {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = message;
  alert.alertStyle = NSAlertStyleInformational;
  if (window) {
    [alert beginSheetModalForWindow:window completionHandler:nil];
  } else {
    [alert runModal];
  }
}

static const char *RosetteUTF8OrEmpty(NSString *value) {
  return value ? value.UTF8String : "";
}

static void RosetteLogVideoCaptureError(NSString *stage, NSError *error) {
  NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
  fprintf(stderr,
          "macho-processor: window video capture error: stage=%s domain=%s code=%ld description=%s failure_reason=%s underlying_domain=%s underlying_code=%ld underlying_description=%s\n",
          RosetteUTF8OrEmpty(stage), RosetteUTF8OrEmpty(error.domain),
          (long)error.code, RosetteUTF8OrEmpty(error.localizedDescription),
          RosetteUTF8OrEmpty(error.localizedFailureReason),
          RosetteUTF8OrEmpty(underlying.domain), (long)underlying.code,
          RosetteUTF8OrEmpty(underlying.localizedDescription));
}

static BOOL RosetteScreenFrameIsComplete(CMSampleBufferRef sampleBuffer,
                                         NSInteger *statusOut) {
  if (statusOut) *statusOut = -1;
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
  if (!attachments || CFArrayGetCount(attachments) == 0) return NO;
  CFDictionaryRef frameAttachments = CFArrayGetValueAtIndex(attachments, 0);
  CFNumberRef statusNumber = (CFNumberRef)CFDictionaryGetValue(
      frameAttachments, (__bridge CFStringRef)SCStreamFrameInfoStatus);
  int64_t rawStatus = -1;
  if (!statusNumber || !CFNumberGetValue(statusNumber, kCFNumberSInt64Type, &rawStatus)) {
    return NO;
  }
  if (statusOut) *statusOut = (NSInteger)rawStatus;
  return rawStatus == SCFrameStatusComplete;
}

static BOOL RosetteGfxrCaptureIsArmed(void) {
  const char *raw = getenv("ROSETTE_VULKAN_GFXR");
  if (!raw || raw[0] == '\0') return NO;
  return strcmp(raw, "0") != 0 && strcasecmp(raw, "off") != 0;
}

static NSDictionary<NSFileAttributeKey, id> *RosetteFileAttributes(NSString *path) {
  return [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
}

static NSRect RosetteWindowContentRectOnScreen(NSWindow *window) {
  NSView *contentView = window.contentView;
  if (!contentView) return NSZeroRect;
  NSRect contentRectInWindow = [contentView convertRect:contentView.bounds toView:nil];
  return [window convertRectToScreen:contentRectInWindow];
}

static NSRect RosetteWindowContentRectRelativeToFrame(NSWindow *window) {
  NSRect frame = window.frame;
  NSRect content = RosetteWindowContentRectOnScreen(window);
  return NSMakeRect(content.origin.x - frame.origin.x,
                    content.origin.y - frame.origin.y,
                    content.size.width, content.size.height);
}

static CGImageRef RosetteCreateWindowContentImage(NSWindow *window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  CGImageRef fullImage = CGWindowListCreateImage(
      CGRectNull, kCGWindowListOptionIncludingWindow,
      (CGWindowID)window.windowNumber, kCGWindowImageBoundsIgnoreFraming);
#pragma clang diagnostic pop
  if (!fullImage) return nil;

  NSRect windowFrame = window.frame;
  NSRect contentRect = RosetteWindowContentRectRelativeToFrame(window);
  if (windowFrame.size.width <= 0.0 || windowFrame.size.height <= 0.0 ||
      NSIsEmptyRect(contentRect)) {
    CGImageRelease(fullImage);
    return nil;
  }

  const CGFloat scaleX = (CGFloat)CGImageGetWidth(fullImage) / windowFrame.size.width;
  const CGFloat scaleY = (CGFloat)CGImageGetHeight(fullImage) / windowFrame.size.height;
  const CGFloat top = windowFrame.size.height - contentRect.origin.y - contentRect.size.height;
  CGRect crop = CGRectMake(round(contentRect.origin.x * scaleX), round(top * scaleY),
                           round(contentRect.size.width * scaleX),
                           round(contentRect.size.height * scaleY));
  crop = CGRectIntersection(crop, CGRectMake(0, 0, CGImageGetWidth(fullImage),
                                              CGImageGetHeight(fullImage)));
  CGImageRef contentImage = (CGRectIsNull(crop) || CGRectIsEmpty(crop))
      ? nil : CGImageCreateWithImageInRect(fullImage, crop);
  CGImageRelease(fullImage);
  return contentImage;
}

@interface RosetteWindowVideoCapture : NSObject <SCStreamOutput, SCStreamDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic, strong) AVAssetWriter *writer;
@property(nonatomic, strong) AVAssetWriterInput *writerInput;
@property(nonatomic, strong) AVAssetWriterInput *audioWriterInput;
@property(nonatomic, strong) NSURL *temporaryURL;
@property(nonatomic, strong) dispatch_queue_t sampleQueue;
@property(nonatomic, assign) CMTime sessionStartTime;
@property(atomic, assign) BOOL stopping;
@property(atomic, assign) BOOL started;
@property(atomic, assign) BOOL finishedSuccessfully;
@property(nonatomic, assign) uint64_t appendedVideoFrames;
@property(nonatomic, assign) uint64_t appendedAudioSamples;
@property(nonatomic, assign) uint64_t skippedNonCompleteFrames;
@property(nonatomic, assign) uint64_t framesMissingStatus;
@property(nonatomic, copy) void (^didFinish)(void);
- (void)startForWindow:(NSWindow *)window;
- (void)stop;
- (void)finishWithTitle:(nullable NSString *)title message:(nullable NSString *)message;
@end

@implementation RosetteWindowVideoCapture

- (instancetype)init {
  self = [super init];
  if (self) {
    _sampleQueue = dispatch_queue_create("org.rosette.window-capture",
                                         DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)startForWindow:(NSWindow *)window {
  self.window = window;
  NSString *temporaryName = [NSString stringWithFormat:@"rosette-capture-%@.mov",
                             [NSUUID UUID].UUIDString];
  self.temporaryURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
      URLByAppendingPathComponent:temporaryName];
  self.finishedSuccessfully = NO;
  const CGWindowID wantedWindow = (CGWindowID)window.windowNumber;
  __weak RosetteWindowVideoCapture *weakSelf = self;
  [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                            onScreenWindowsOnly:YES
                                              completionHandler:^(SCShareableContent *content, NSError *error) {
    RosetteWindowVideoCapture *strongSelf = weakSelf;
    if (!strongSelf) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error || !content) {
        [strongSelf finishWithTitle:@"Video capture unavailable"
                            message:error.localizedDescription ?: @"macOS did not provide shareable windows."];
        return;
      }
      SCWindow *target = nil;
      for (SCWindow *candidate in content.windows) {
        if (candidate.windowID == wantedWindow) {
          target = candidate;
          break;
        }
      }
      if (!target) {
        [strongSelf finishWithTitle:@"Window not available"
                            message:@"Keep the Rosette game window visible, then start video capture again."];
        return;
      }

      SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
      NSRect contentRect = RosetteWindowContentRectRelativeToFrame(window);
      if (NSIsEmptyRect(contentRect)) {
        [strongSelf finishWithTitle:@"Video capture unavailable"
                            message:@"Rosette could not determine the game-content rectangle."];
        return;
      }

      // A desktop-independent single-window filter always captures the
      // window's full bounds; ScreenCaptureKit ignores sourceRect for that
      // filter style. Use a display filter constrained to this one window so
      // sourceRect can crop out the Rosette titlebar and toolbar controls.
      SCDisplay *targetDisplay = nil;
      CGFloat largestVisibleArea = 0.0;
      for (SCDisplay *display in content.displays) {
        CGRect visible = CGRectIntersection(display.frame, target.frame);
        if (CGRectIsNull(visible) || CGRectIsEmpty(visible)) continue;
        CGFloat visibleArea = CGRectGetWidth(visible) * CGRectGetHeight(visible);
        if (visibleArea > largestVisibleArea) {
          largestVisibleArea = visibleArea;
          targetDisplay = display;
        }
      }
      if (!targetDisplay) {
        [strongSelf finishWithTitle:@"Video capture unavailable"
                            message:@"Rosette could not find the display containing its game window."];
        return;
      }
      SCContentFilter *filter = [[SCContentFilter alloc]
          initWithDisplay:targetDisplay includingWindows:@[target]];
      // SCContentFilter.pointPixelScale is not implemented by every macOS
      // version we support. AppKit's window scale supplies the same points to
      // pixels conversion without sending that optional ScreenCaptureKit selector.
      CGFloat pointPixelScale = window.backingScaleFactor;
      if (!isfinite(pointPixelScale) || pointPixelScale <= 0.0) {
        pointPixelScale = 1.0;
      }
      CGRect sourceRect = target.frame;
      sourceRect.origin.x += contentRect.origin.x;
      sourceRect.origin.y += window.frame.size.height - contentRect.origin.y - contentRect.size.height;
      sourceRect.size = contentRect.size;
      configuration.sourceRect = sourceRect;
      configuration.width = (size_t)MAX((NSInteger)llround(contentRect.size.width * pointPixelScale), 1);
      configuration.height = (size_t)MAX((NSInteger)llround(contentRect.size.height * pointPixelScale), 1);
      configuration.pixelFormat = kCVPixelFormatType_32BGRA;
      configuration.minimumFrameInterval = CMTimeMake(1, 30);
      configuration.queueDepth = 5;
      configuration.showsCursor = NO;
      configuration.capturesAudio = YES;
      configuration.sampleRate = 48000;
      configuration.channelCount = 2;
      configuration.excludesCurrentProcessAudio = NO;
      strongSelf.stream = [[SCStream alloc] initWithFilter:filter
                                             configuration:configuration
                                                  delegate:strongSelf];
      NSError *addError = nil;
      if (![strongSelf.stream addStreamOutput:strongSelf
                                          type:SCStreamOutputTypeScreen
                            sampleHandlerQueue:strongSelf.sampleQueue
                                         error:&addError]) {
        RosetteLogVideoCaptureError(@"add-screen-output", addError);
        [strongSelf finishWithTitle:@"Video capture unavailable"
                            message:addError.localizedDescription ?: @"Could not attach the screen-capture output."];
        return;
      }
      if (![strongSelf.stream addStreamOutput:strongSelf
                                          type:SCStreamOutputTypeAudio
                            sampleHandlerQueue:strongSelf.sampleQueue
                                         error:&addError]) {
        RosetteLogVideoCaptureError(@"add-audio-output", addError);
        [strongSelf finishWithTitle:@"Video capture unavailable"
                            message:addError.localizedDescription ?: @"Could not attach the audio-capture output."];
        return;
      }
      [strongSelf.stream startCaptureWithCompletionHandler:^(NSError *startError) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (startError) {
            RosetteLogVideoCaptureError(@"stream-start", startError);
            [strongSelf finishWithTitle:@"Video capture failed"
                                message:startError.localizedDescription ?: @"ScreenCaptureKit could not start."];
            return;
          }
          strongSelf.started = YES;
          fprintf(stderr, "macho-processor: window video capture started\n");
        });
      }];
    });
  }];
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
          ofType:(SCStreamOutputType)type {
  (void)stream;
  if (self.stopping || !CMSampleBufferDataIsReady(sampleBuffer)) {
    return;
  }
  if (type == SCStreamOutputTypeScreen) {
    NSInteger frameStatus = -1;
    if (!RosetteScreenFrameIsComplete(sampleBuffer, &frameStatus)) {
      if (frameStatus < 0) {
        self.framesMissingStatus++;
        if (self.framesMissingStatus <= 3) {
          fprintf(stderr,
                  "macho-processor: window video capture skipped screen sample: reason=missing_frame_status count=%llu\n",
                  (unsigned long long)self.framesMissingStatus);
        }
      } else {
        self.skippedNonCompleteFrames++;
        if (self.skippedNonCompleteFrames <= 3) {
          fprintf(stderr,
                  "macho-processor: window video capture skipped screen sample: reason=non_complete_frame status=%ld count=%llu\n",
                  (long)frameStatus, (unsigned long long)self.skippedNonCompleteFrames);
        }
      }
      return;
    }
  }
  if (type == SCStreamOutputTypeAudio) {
    AVAssetWriterInput *audioInput = self.audioWriterInput;
    if (!self.writer || !audioInput ||
        CMTIME_COMPARE_INLINE(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), <,
                              self.sessionStartTime)) {
      return;
    }
    if (audioInput.readyForMoreMediaData &&
        ![audioInput appendSampleBuffer:sampleBuffer]) {
      NSError *writerError = self.writer.error;
      RosetteLogVideoCaptureError(@"audio-sample-append", writerError);
      NSString *message = writerError.localizedDescription ?: @"The movie writer stopped accepting audio samples.";
      [self finishWithTitle:@"Video capture stopped" message:message];
    } else if (audioInput.readyForMoreMediaData) {
      self.appendedAudioSamples++;
    }
    return;
  }
  if (type != SCStreamOutputTypeScreen) return;
  if (!self.writer) {
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!format) return;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
    NSError *writerError = nil;
    self.writer = [[AVAssetWriter alloc] initWithURL:self.temporaryURL
                                            fileType:AVFileTypeQuickTimeMovie
                                               error:&writerError];
    if (!self.writer || dimensions.width <= 0 || dimensions.height <= 0) {
      [self finishWithTitle:@"Video capture failed"
                    message:writerError.localizedDescription ?: @"The captured frame had no usable video format."];
      return;
    }
    NSDictionary *settings = @{
      AVVideoCodecKey : AVVideoCodecTypeH264,
      AVVideoWidthKey : @(dimensions.width),
      AVVideoHeightKey : @(dimensions.height),
    };
    self.writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                           outputSettings:settings
                                                         sourceFormatHint:format];
    self.writerInput.expectsMediaDataInRealTime = YES;
    if (![self.writer canAddInput:self.writerInput]) {
      [self finishWithTitle:@"Video capture failed"
                    message:@"The system video encoder rejected the window format."];
      return;
    }
    [self.writer addInput:self.writerInput];
    NSDictionary *audioSettings = @{
      AVFormatIDKey : @(kAudioFormatMPEG4AAC),
      AVSampleRateKey : @48000,
      AVNumberOfChannelsKey : @2,
      AVEncoderBitRateKey : @128000,
    };
    self.audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                outputSettings:audioSettings];
    self.audioWriterInput.expectsMediaDataInRealTime = YES;
    if (![self.writer canAddInput:self.audioWriterInput]) {
      [self finishWithTitle:@"Video capture failed"
                    message:@"The system movie writer rejected the captured audio format."];
      return;
    }
    [self.writer addInput:self.audioWriterInput];
    if (![self.writer startWriting]) {
      RosetteLogVideoCaptureError(@"writer-start", self.writer.error);
      NSString *message = self.writer.error.localizedDescription ?: @"Could not open the movie file for writing.";
      [self finishWithTitle:@"Video capture failed" message:message];
      return;
    }
    self.sessionStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    [self.writer startSessionAtSourceTime:self.sessionStartTime];
  }
  if (self.writerInput.readyForMoreMediaData &&
      ![self.writerInput appendSampleBuffer:sampleBuffer]) {
    NSError *writerError = self.writer.error;
    RosetteLogVideoCaptureError(@"video-frame-append", writerError);
    NSString *message = writerError.localizedDescription ?: @"The movie writer stopped accepting frames.";
    [self finishWithTitle:@"Video capture stopped" message:message];
  } else if (self.writerInput.readyForMoreMediaData) {
    self.appendedVideoFrames++;
  }
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
  (void)stream;
  if (error && !self.stopping) {
    RosetteLogVideoCaptureError(@"stream-stop", error);
    [self finishWithTitle:@"Video capture stopped" message:error.localizedDescription];
  } else if (error) {
    RosetteLogVideoCaptureError(@"stream-stop-during-finish", error);
  }
}

- (void)stop {
  [self finishWithTitle:nil message:nil];
}

- (void)finishWithTitle:(NSString *)title message:(NSString *)message {
  if (self.stopping) return;
  self.stopping = YES;
  __weak RosetteWindowVideoCapture *weakSelf = self;
  void (^finishAfterStoppingStream)(NSError *) = ^(NSError *stopError) {
    RosetteWindowVideoCapture *strongSelf = weakSelf;
    if (!strongSelf) return;
    dispatch_async(strongSelf.sampleQueue, ^{
      AVAssetWriter *writer = strongSelf.writer;
      AVAssetWriterInput *input = strongSelf.writerInput;
      AVAssetWriterInput *audioInput = strongSelf.audioWriterInput;
      fprintf(stderr,
              "macho-processor: window video capture finishing: title=%s message=%s video_frames=%llu audio_samples=%llu skipped_non_complete_frames=%llu frames_missing_status=%llu\n",
              RosetteUTF8OrEmpty(title), RosetteUTF8OrEmpty(message),
              (unsigned long long)strongSelf.appendedVideoFrames,
              (unsigned long long)strongSelf.appendedAudioSamples,
              (unsigned long long)strongSelf.skippedNonCompleteFrames,
              (unsigned long long)strongSelf.framesMissingStatus);
      if (stopError) {
        RosetteLogVideoCaptureError(@"stream-stop-completion", stopError);
      }
      if (!writer || writer.status != AVAssetWriterStatusWriting) {
        if (writer) {
          fprintf(stderr,
                  "macho-processor: window video capture writer not writing at stop: status=%ld\n",
                  (long)writer.status);
          RosetteLogVideoCaptureError(@"writer-not-writing", writer.error);
        }
        if (writer) [writer cancelWriting];
        dispatch_async(dispatch_get_main_queue(), ^{
          strongSelf.finishedSuccessfully = NO;
          if (strongSelf.temporaryURL) {
            [[NSFileManager defaultManager] removeItemAtURL:strongSelf.temporaryURL error:nil];
          }
          if (title) {
            RosetteToolbarShowAlert(strongSelf.window, title,
                message ?: writer.error.localizedDescription ?: stopError.localizedDescription ?: @"Video capture did not complete.");
          } else {
            RosetteToolbarShowAlert(strongSelf.window, @"No video frames captured",
                stopError.localizedDescription ?: @"The window produced no frames while capture was active.");
          }
          strongSelf.stream = nil;
          strongSelf.writer = nil;
          strongSelf.writerInput = nil;
          strongSelf.audioWriterInput = nil;
          strongSelf.started = NO;
          strongSelf.stopping = NO;
          if (strongSelf.didFinish) strongSelf.didFinish();
        });
        return;
      }
      if (input) [input markAsFinished];
      if (audioInput) [audioInput markAsFinished];
      [writer finishWritingWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
          strongSelf.finishedSuccessfully = !title && !stopError &&
              writer.status == AVAssetWriterStatusCompleted;
          fprintf(stderr,
                  "macho-processor: window video capture writer finished: status=%ld success=%s\n",
                  (long)writer.status, strongSelf.finishedSuccessfully ? "true" : "false");
          if (!strongSelf.finishedSuccessfully) {
            RosetteLogVideoCaptureError(@"writer-finish", writer.error ?: stopError);
          }
          strongSelf.stream = nil;
          strongSelf.writer = nil;
          strongSelf.writerInput = nil;
          strongSelf.audioWriterInput = nil;
          strongSelf.started = NO;
          strongSelf.stopping = NO;
          if (title) {
            RosetteToolbarShowAlert(strongSelf.window, title,
                message ?: writer.error.localizedDescription ?: stopError.localizedDescription ?: @"Video capture failed.");
          } else if (strongSelf.finishedSuccessfully) {
            // The toolbar controller asks for a destination only after the
            // stream and asset writer have both stopped cleanly.
          } else {
            RosetteToolbarShowAlert(strongSelf.window, @"Video capture failed",
                                    writer.error.localizedDescription ?: stopError.localizedDescription ?: @"The movie file did not finish cleanly.");
          }
          if (!strongSelf.finishedSuccessfully && strongSelf.temporaryURL) {
            [[NSFileManager defaultManager] removeItemAtURL:strongSelf.temporaryURL error:nil];
          }
          if (strongSelf.didFinish) strongSelf.didFinish();
        });
      }];
    });
  };
  SCStream *stream = self.stream;
  if (stream) {
    [stream stopCaptureWithCompletionHandler:finishAfterStoppingStream];
  } else {
    finishAfterStoppingStream(nil);
  }
}

@end

@interface RosetteNativeToolbarController : NSObject <NSToolbarDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) NSButton *fpsButton;
@property(nonatomic, strong) NSSlider *brightnessSlider;
@property(nonatomic, strong) NSToolbarItem *videoItem;
@property(nonatomic, strong) RosetteWindowVideoCapture *videoCapture;
@property(nonatomic, assign) uint64_t gfxrGeneration;
@property(nonatomic, assign) BOOL gfxrCapturePending;
- (void)installOnWindow:(NSWindow *)window;
- (void)pollGfxrAtPath:(NSString *)sourcePath
           generation:(uint64_t)generation
         baselineSize:(unsigned long long)baselineSize
         baselineDate:(NSDate *)baselineDate
         previousSize:(unsigned long long)previousSize
         previousDate:(NSDate *)previousDate
         stableChecks:(NSUInteger)stableChecks
             attempts:(NSUInteger)attempts;
- (void)saveCompletedGfxrAtPath:(NSString *)sourcePath generation:(uint64_t)generation;
@end

@implementation RosetteNativeToolbarController

- (void)installOnWindow:(NSWindow *)window {
  if (!window) return;
  self.window = window;
  NSToolbar *toolbar = window.toolbar;
  if (!toolbar) {
    toolbar = [[NSToolbar alloc] initWithIdentifier:@"org.rosette.game-window"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    window.toolbar = toolbar;
  } else {
    toolbar.delegate = self;
  }
  toolbar.visible = YES;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
  (void)toolbar;
  return @[kScreenshotItem, kVideoItem, kGfxrItem, NSToolbarSpaceItemIdentifier,
           kFPSItem, kBrightnessItem, NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
  (void)toolbar;
  return @[kScreenshotItem, kVideoItem, kGfxrItem, NSToolbarSpaceItemIdentifier,
           kFPSItem, kBrightnessItem];
}

- (NSToolbarItem *)buttonItem:(NSToolbarItemIdentifier)identifier
                         label:(NSString *)label
                          icon:(NSString *)icon
                        action:(SEL)action
                       tooltip:(NSString *)tooltip {
  NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
  item.label = label;
  item.paletteLabel = label;
  item.toolTip = tooltip;
  item.image = [NSImage imageWithSystemSymbolName:icon accessibilityDescription:label];
  item.target = self;
  item.action = action;
  return item;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag {
  (void)toolbar;
  (void)flag;
  if ([identifier isEqualToString:kScreenshotItem]) {
    return [self buttonItem:identifier label:@"Screenshot" icon:@"camera"
                     action:@selector(captureScreenshot:)
                    tooltip:@"Save a screenshot of the Rosette game window"];
  }
  if ([identifier isEqualToString:kVideoItem]) {
    NSToolbarItem *item = [self buttonItem:identifier label:@"Record Video"
                                      icon:@"record.circle"
                                    action:@selector(toggleVideoCapture:)
                                   tooltip:@"Record or stop recording this game window"];
    self.videoItem = item;
    return item;
  }
  if ([identifier isEqualToString:kGfxrItem]) {
    return [self buttonItem:identifier label:@"Capture GFXR" icon:@"record.circle"
                     action:@selector(saveGfxrCapture:)
                    tooltip:@"Capture one Vulkan frame, then choose where to save the dump"];
  }
  if ([identifier isEqualToString:kFPSItem]) {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"FPS";
    item.paletteLabel = @"FPS counter";
    item.toolTip = @"Show or hide the native present-rate counter";
    NSButton *button = [NSButton checkboxWithTitle:@"FPS" target:self
                                            action:@selector(toggleFPS:)];
    button.state = NSControlStateValueOn;
    [button setButtonType:NSButtonTypeSwitch];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:48.0].active = YES;
    item.view = button;
    self.fpsButton = button;
    return item;
  }
  if ([identifier isEqualToString:kBrightnessItem]) {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"Brightness";
    item.paletteLabel = @"Post brightness";
    item.toolTip = @"Apply a display-space brightness lift over the game image";
    NSTextField *label = [NSTextField labelWithString:@"Brightness"];
    NSSlider *slider = [NSSlider sliderWithValue:0.0 minValue:0.0 maxValue:0.35
                                          target:self action:@selector(changeBrightness:)];
    slider.numberOfTickMarks = 0;
    slider.continuous = YES;
    [slider.widthAnchor constraintEqualToConstant:112.0].active = YES;
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 185, 28)];
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:slider];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 7.0;
    [stack.widthAnchor constraintEqualToConstant:185.0].active = YES;
    [stack.heightAnchor constraintEqualToConstant:28.0].active = YES;
    item.view = stack;
    self.brightnessSlider = slider;
    return item;
  }
  return nil;
}

- (void)captureScreenshot:(id)sender {
  (void)sender;
  NSWindow *window = self.window;
  if (!window) return;
  CGImageRef image = RosetteCreateWindowContentImage(window);
  if (!image) {
    RosetteToolbarShowAlert(window, @"Screenshot failed",
                            @"macOS could not return the game-content image. Check Screen Recording permission in System Settings, then retry.");
    return;
  }
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
  CGImageRelease(image);
  NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  if (!png) {
    RosetteToolbarShowAlert(window, @"Screenshot failed", @"Could not encode the captured window as PNG.");
    return;
  }
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.allowedContentTypes = @[UTTypePNG];
  panel.nameFieldStringValue = @"Rosette Screenshot.png";
  [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    if (response != NSModalResponseOK || !panel.URL) return;
    NSError *error = nil;
    if (![png writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
      RosetteToolbarShowAlert(window, @"Screenshot save failed",
                              error.localizedDescription ?: @"Could not write the PNG file.");
    }
  }];
}

- (void)toggleFPS:(NSButton *)sender {
  const BOOL enabled = sender.state == NSControlStateValueOn;
  (void)rosette_macho_native_window_set_fps_visible(enabled ? 1 : 0);
}

- (void)changeBrightness:(NSSlider *)sender {
  (void)rosette_macho_native_window_set_post_brightness((float)sender.doubleValue);
}

- (void)toggleVideoCapture:(id)sender {
  (void)sender;
  if (self.videoCapture) {
    if (self.videoCapture.stopping) {
      RosetteToolbarShowAlert(self.window, @"Video capture is stopping",
                              @"Wait for the movie file to finish writing.");
      return;
    }
    if (!self.videoCapture.started) {
      RosetteToolbarShowAlert(self.window, @"Video capture is starting",
                              @"Wait for ScreenCaptureKit to start, then press Stop Video.");
      return;
    }
    [self.videoCapture stop];
    return;
  }
  NSWindow *window = self.window;
  if (!window) return;
  RosetteWindowVideoCapture *capture = [[RosetteWindowVideoCapture alloc] init];
  self.videoCapture = capture;
  __weak RosetteNativeToolbarController *weakController = self;
  __weak RosetteWindowVideoCapture *weakCapture = capture;
  capture.didFinish = ^{
    RosetteNativeToolbarController *strongController = weakController;
    RosetteWindowVideoCapture *strongCapture = weakCapture;
    if (!strongController || !strongCapture || strongController.videoCapture != strongCapture) return;
    strongController.videoCapture = nil;
    if (strongController.videoItem) {
      strongController.videoItem.label = @"Record Video";
      strongController.videoItem.paletteLabel = @"Record Video";
      strongController.videoItem.image = [NSImage imageWithSystemSymbolName:@"record.circle"
                                                 accessibilityDescription:@"Record Video"];
    }
    if (!strongCapture.finishedSuccessfully || !strongCapture.temporaryURL) return;

    NSWindow *captureWindow = strongController.window;
    NSURL *temporaryURL = strongCapture.temporaryURL;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeQuickTimeMovie];
    panel.nameFieldStringValue = @"Rosette Capture.mov";
    [panel beginSheetModalForWindow:captureWindow completionHandler:^(NSModalResponse response) {
      NSFileManager *fileManager = [NSFileManager defaultManager];
      if (response != NSModalResponseOK || !panel.URL) {
        [fileManager removeItemAtURL:temporaryURL error:nil];
        RosetteToolbarShowAlert(captureWindow, @"Recording discarded",
                                @"The completed recording was not saved.");
        return;
      }

      NSURL *destinationURL = panel.URL;
      BOOL hasScopedAccess = [destinationURL startAccessingSecurityScopedResource];
      NSURL *directoryURL = [destinationURL URLByDeletingLastPathComponent];
      NSString *stagingName = [NSString stringWithFormat:@".rosette-capture-%@.mov",
                               [NSUUID UUID].UUIDString];
      NSURL *stagingURL = [directoryURL URLByAppendingPathComponent:stagingName];
      NSError *saveError = nil;
      BOOL saved = [fileManager copyItemAtURL:temporaryURL toURL:stagingURL error:&saveError];
      if (saved && [fileManager fileExistsAtPath:destinationURL.path]) {
        saved = [fileManager replaceItemAtURL:destinationURL
                                withItemAtURL:stagingURL
                               backupItemName:nil
                                      options:0
                             resultingItemURL:nil
                                        error:&saveError];
      } else if (saved) {
        saved = [fileManager moveItemAtURL:stagingURL toURL:destinationURL error:&saveError];
      }
      if (!saved) {
        [fileManager removeItemAtURL:stagingURL error:nil];
        if (hasScopedAccess) [destinationURL stopAccessingSecurityScopedResource];
        RosetteToolbarShowAlert(captureWindow, @"Video save failed",
                                saveError.localizedDescription ?: @"Could not move the completed recording to the selected location.");
        return;
      }
      [fileManager removeItemAtURL:temporaryURL error:nil];
      if (hasScopedAccess) [destinationURL stopAccessingSecurityScopedResource];
      RosetteToolbarShowAlert(captureWindow, @"Video saved",
                              [destinationURL.path stringByAbbreviatingWithTildeInPath]);
    }];
  };
  if (self.videoItem) {
    self.videoItem.label = @"Stop Video";
    self.videoItem.paletteLabel = @"Stop video recording";
    self.videoItem.image = [NSImage imageWithSystemSymbolName:@"stop.circle.fill"
                                     accessibilityDescription:@"Stop video"];
  }
  [capture startForWindow:window];
}

- (void)saveGfxrCapture:(id)sender {
  (void)sender;
  NSWindow *window = self.window;
  if (self.gfxrCapturePending) {
    RosetteToolbarShowAlert(window, @"GFXR capture is already pending",
        @"Finish or cancel the current capture before starting another one.");
    return;
  }
  if (!RosetteGfxrCaptureIsArmed()) {
    RosetteToolbarShowAlert(window, @"Vulkan capture is not armed",
        @"GFXReconstruct must be loaded before Vulkan creates its instance. Quit and relaunch Rosette with ROSETTE_VULKAN_GFXR=hotkey, then use Capture GFXR.");
    return;
  }
  const char *capture_path = getenv("GFXRECON_CAPTURE_FILE");
  if (!capture_path || capture_path[0] == '\0') {
    RosetteToolbarShowAlert(window, @"Capture output is not configured",
        @"The capture layer is armed but did not publish GFXRECON_CAPTURE_FILE. Restart with the Rosette Vulkan capture launcher and retry.");
    return;
  }
  NSString *sourcePath = [NSString stringWithUTF8String:capture_path];
  NSDictionary *baseline = RosetteFileAttributes(sourcePath);
  unsigned long long baselineSize = [baseline[NSFileSize] unsignedLongLongValue];
  NSDate *baselineDate = baseline[NSFileModificationDate];
  self.gfxrCapturePending = YES;
  const uint64_t generation = ++self.gfxrGeneration;
  RosetteToolbarShowAlert(window, @"Ready for GFXR capture",
      [NSString stringWithFormat:@"Press the configured GFXReconstruct hotkey (%s by default) once in the game. After the dump finishes, choose where to save it.",
          getenv("GFXRECON_CAPTURE_TRIGGER") ?: "F10"]);
  [self pollGfxrAtPath:sourcePath generation:generation
        baselineSize:baselineSize baselineDate:baselineDate previousSize:0
        previousDate:nil stableChecks:0 attempts:0];
}

- (void)pollGfxrAtPath:(NSString *)sourcePath
            generation:(uint64_t)generation
          baselineSize:(unsigned long long)baselineSize
          baselineDate:(NSDate *)baselineDate
          previousSize:(unsigned long long)previousSize
          previousDate:(NSDate *)previousDate
          stableChecks:(NSUInteger)stableChecks
              attempts:(NSUInteger)attempts {
  if (generation != self.gfxrGeneration) return;
  NSDictionary *attributes = RosetteFileAttributes(sourcePath);
  unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
  NSDate *date = attributes[NSFileModificationDate];
  const BOOL changed = attributes && size > 0 &&
      (size != baselineSize || (date && ![date isEqualToDate:baselineDate]));
  const BOOL stable = changed && size == previousSize &&
      ((date == nil && previousDate == nil) || [date isEqualToDate:previousDate]);
  if (stable && stableChecks >= 2) {
    [self saveCompletedGfxrAtPath:sourcePath generation:generation];
    return;
  }
  if (attempts >= 240) {
    self.gfxrCapturePending = NO;
    RosetteToolbarShowAlert(self.window, @"No new GFXR capture detected",
        @"The capture file did not change within two minutes. Confirm the Vulkan layer is armed and trigger a one-frame capture before retrying.");
    return;
  }
  const NSUInteger nextStableChecks = stable ? stableChecks + 1 : 0;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                 dispatch_get_main_queue(), ^{
    [self pollGfxrAtPath:sourcePath generation:generation
          baselineSize:baselineSize baselineDate:baselineDate previousSize:size
          previousDate:date stableChecks:nextStableChecks attempts:attempts + 1];
  });
}

- (void)saveCompletedGfxrAtPath:(NSString *)sourcePath generation:(uint64_t)generation {
  if (generation != self.gfxrGeneration) return;
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gfxr"] ?: UTTypeData];
  panel.nameFieldStringValue = @"Rosette Vulkan Capture.gfxr";
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (generation != self.gfxrGeneration) return;
    self.gfxrCapturePending = NO;
    if (response != NSModalResponseOK || !panel.URL) return;
    NSString *destination = panel.URL.path;
    if ([sourcePath isEqualToString:destination]) {
      RosetteToolbarShowAlert(self.window, @"GFXR capture saved",
                              @"The completed capture is already at the selected path.");
      return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *temporary = [destination stringByAppendingFormat:@".rosette-%@",
                          NSUUID.UUID.UUIDString];
    NSError *copyError = nil;
    if (![manager copyItemAtPath:sourcePath toPath:temporary error:&copyError]) {
      RosetteToolbarShowAlert(self.window, @"GFXR save failed",
          copyError.localizedDescription ?: @"Could not stage the capture file.");
      return;
    }
    NSURL *destinationURL = [NSURL fileURLWithPath:destination];
    NSURL *temporaryURL = [NSURL fileURLWithPath:temporary];
    BOOL saved = NO;
    if ([manager fileExistsAtPath:destination]) {
      saved = [manager replaceItemAtURL:destinationURL
                          withItemAtURL:temporaryURL
                         backupItemName:nil
                                options:0
                       resultingItemURL:nil
                                  error:&copyError];
    } else {
      saved = [manager moveItemAtURL:temporaryURL toURL:destinationURL error:&copyError];
    }
    if (saved) {
      RosetteToolbarShowAlert(self.window, @"GFXR capture saved",
          [destination stringByAbbreviatingWithTildeInPath]);
    } else {
      [manager removeItemAtPath:temporary error:nil];
      RosetteToolbarShowAlert(self.window, @"GFXR save failed",
          copyError.localizedDescription ?: @"Could not copy the capture file.");
    }
  }];
}

@end

static RosetteNativeToolbarController *g_toolbar_controller;

void rosette_macho_native_toolbar_install(NSWindow *window) {
  if (!window) return;
  if (!g_toolbar_controller) {
    g_toolbar_controller = [[RosetteNativeToolbarController alloc] init];
  }
  [g_toolbar_controller installOnWindow:window];
}
