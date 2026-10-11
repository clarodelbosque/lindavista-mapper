#include "WebPanel.h"

#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>

#include <algorithm>
#include <cmath>

@class VMPanelDivider;

// Lays out the panel (left) and the 3D view (the rest of the window), with a draggable
// divider on the panel's right edge.
@interface VMPanelContainer : NSView
@property (nonatomic, weak) NSView* panel;
@property (nonatomic, weak) NSView* stage;
@property (nonatomic, strong) VMPanelDivider* divider;
@property (nonatomic) BOOL panelVisible;
@property (nonatomic) BOOL collapsed;
@property (nonatomic) CGFloat panelWidth;  // expanded width, kept while collapsed
- (void)layoutPanes;
- (void)dragPanelTo:(CGFloat)x;
@end

// An 8 pt strip centred on the panel's right edge: resize cursor, a teal line while
// hovered or dragged (like shadcn's resizable handle), and the drag itself.
@interface VMPanelDivider : NSView
@property (nonatomic, weak) VMPanelContainer* container;
@end

@implementation VMPanelDivider {
    CALayer* _line;
    BOOL _hover;
    BOOL _dragging;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;  // composites above the Metal view
        _line = [CALayer layer];
        _line.backgroundColor = [NSColor colorWithSRGBRed:0.0 green:0.63 blue:0.75 alpha:1.0].CGColor;
        _line.hidden = YES;
        [self.layer addSublayer:_line];
    }
    return self;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _line.frame = CGRectMake(NSMidX(self.bounds) - 1, 0, 2, self.bounds.size.height);
    [CATransaction commit];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* area in self.trackingAreas) [self removeTrackingArea:area];
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingCursorUpdate | NSTrackingActiveAlways |
                                    NSTrackingInVisibleRect;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil]];
}
- (void)updateLine { _line.hidden = !(_hover || _dragging); }
- (void)cursorUpdate:(NSEvent*)event { [NSCursor.resizeLeftRightCursor set]; }
- (void)mouseEntered:(NSEvent*)event {
    _hover = YES;
    [NSCursor.resizeLeftRightCursor set];
    [self updateLine];
}
- (void)mouseExited:(NSEvent*)event {
    _hover = NO;
    if (!_dragging) [NSCursor.arrowCursor set];
    [self updateLine];
}
- (void)mouseDown:(NSEvent*)event {
    _dragging = YES;
    [self updateLine];
}
- (void)mouseDragged:(NSEvent*)event {
    [_container dragPanelTo:[_container convertPoint:event.locationInWindow fromView:nil].x];
    [NSCursor.resizeLeftRightCursor set];
}
- (void)mouseUp:(NSEvent*)event {
    _dragging = NO;
    if (!_hover) [NSCursor.arrowCursor set];
    [self updateLine];
}
@end

@implementation VMPanelContainer
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize { [self layoutPanes]; }
- (CGFloat)clampWidth:(CGFloat)width {
    CGFloat maxWidth = std::min(WebPanel::kMaxWidth, self.bounds.size.width - WebPanel::kMinStageWidth);
    return std::clamp(width, WebPanel::kMinWidth, std::max(WebPanel::kMinWidth, maxWidth));
}
- (void)layoutPanes {
    NSRect bounds = self.bounds;
    CGFloat width = _collapsed ? WebPanel::kRailWidth : [self clampWidth:_panelWidth];
    CGFloat inset = _panelVisible ? width : 0;
    _panel.hidden = !_panelVisible;
    _divider.hidden = !_panelVisible;
    _panel.frame = NSMakeRect(0, 0, width, bounds.size.height);
    _stage.frame = NSMakeRect(inset, 0, std::max<CGFloat>(1, bounds.size.width - inset), bounds.size.height);
    _divider.frame = NSMakeRect(inset - 4, 0, 8, bounds.size.height);
}
// Below the midpoint between the rail and the minimum width the panel snaps to the rail;
// above it, it follows the pointer between the minimum and maximum widths.
- (void)dragPanelTo:(CGFloat)x {
    if (x < (WebPanel::kRailWidth + WebPanel::kMinWidth) / 2) {
        _collapsed = YES;
    } else {
        _collapsed = NO;
        _panelWidth = [self clampWidth:x];
    }
    [self layoutPanes];
}
@end

// Files dropped on the panel are handled exactly like drops on the 3D view, instead of
// WKWebView's default of navigating to the dropped file.
@interface VMPanelWebView : WKWebView
@property (nonatomic, weak) NSView<NSDraggingDestination>* dropTarget;
@end

@implementation VMPanelWebView
// Like the 3D view: a click works even while Linda Vista Mapper isn't the active app (e.g. its
// window floating over After Effects), instead of only activating the window.
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return [_dropTarget draggingEntered:sender]; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }
- (void)draggingExited:(id<NSDraggingInfo>)sender {}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender { return [_dropTarget performDragOperation:sender]; }
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {}
@end

@interface VMPanelMessageHandler : NSObject <WKScriptMessageHandler> {
@public
    std::function<void(NSDictionary*)> onMessage;
}
@end

@implementation VMPanelMessageHandler
- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    if ([message.body isKindOfClass:NSDictionary.class] && onMessage) onMessage(message.body);
}
@end

// The panel is a single page: block link clicks and other navigations away from it.
@interface VMPanelNavigation : NSObject <WKNavigationDelegate>
@end

@implementation VMPanelNavigation
- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    BOOL allowed = action.navigationType == WKNavigationTypeOther || action.navigationType == WKNavigationTypeReload;
    decisionHandler(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView*)webView { [webView reload]; }
@end

bool WebPanel::install(NSWindow* window, MTKView* view, const std::string& devURL,
                       std::function<void(NSDictionary*)> onAction, std::string& error) {
    NSURL* url = nil;
    NSURL* readAccess = nil;
    if (!devURL.empty()) {
        url = [NSURL URLWithString:@(devURL.c_str())];
    } else {
        NSString* dir = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ui"];
        NSString* index = [dir stringByAppendingPathComponent:@"index.html"];
        if (![NSFileManager.defaultManager fileExistsAtPath:index]) {
            error = std::string("Missing web panel: ") + index.UTF8String + " (run make ui)";
            return false;
        }
        url = [NSURL fileURLWithPath:index];
        readAccess = [NSURL fileURLWithPath:dir isDirectory:YES];
    }
    if (!url) {
        error = "Invalid --ui-dev-url: " + devURL;
        return false;
    }

    VMPanelMessageHandler* handler = [VMPanelMessageHandler new];
    handler->onMessage = [this, onAction](NSDictionary* message) {
        // A (re)loaded page asks for the full state; everything else is for the app.
        if ([message[@"type"] isEqual:@"ready"]) {
            ready_ = true;
            lastState_ = nil;
        } else {
            onAction(message);
        }
    };
    WKWebViewConfiguration* config = [WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:handler name:@"vm"];

    NSRect bounds = window.contentView.bounds;
    container_ = [[VMPanelContainer alloc] initWithFrame:bounds];
    container_.autoresizesSubviews = YES;
    VMPanelWebView* webView = [[VMPanelWebView alloc] initWithFrame:NSMakeRect(0, 0, kDefaultWidth, bounds.size.height)
                                                      configuration:config];
    webView.dropTarget = (NSView<NSDraggingDestination>*)view;
    // Transparent until the page paints, so launch never flashes white.
    @try {
        [webView setValue:@NO forKey:@"drawsBackground"];
    } @catch (NSException*) {
    }
    if (@available(macOS 13.3, *)) webView.inspectable = YES;  // Safari > Develop > Linda Vista Mapper
    navigationDelegate_ = [VMPanelNavigation new];
    webView.navigationDelegate = navigationDelegate_;

    VMPanelDivider* divider = [[VMPanelDivider alloc] initWithFrame:NSZeroRect];
    divider.container = container_;

    window.contentView = container_;
    [container_ addSubview:webView];
    [container_ addSubview:view];
    [container_ addSubview:divider];  // last, so it is hit-tested above both panes
    container_.panel = webView;
    container_.stage = view;
    container_.divider = divider;
    container_.panelVisible = YES;
    container_.panelWidth = kDefaultWidth;
    [container_ layoutPanes];
    [window makeFirstResponder:view];

    webView_ = webView;
    handler_ = handler;
    if (readAccess) [webView loadFileURL:url allowingReadAccessToURL:readAccess];
    else [webView loadRequest:[NSURLRequest requestWithURL:url]];
    return true;
}

void WebPanel::pushState(NSDictionary* state) {
    if (!ready_) return;
    NSData* data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (!data) return;
    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([json isEqualToString:lastState_]) return;
    lastState_ = json;
    NSString* script = [NSString stringWithFormat:@"window.__vmReceive && window.__vmReceive(%@)", json];
    [webView_ evaluateJavaScript:script completionHandler:nil];
}

void WebPanel::setVisible(bool visible) {
    if (container_.panelVisible == visible) return;
    container_.panelVisible = visible;
    [container_ layoutPanes];
    // Keys go back to the 3D view when the panel that had focus disappears.
    if (!visible && container_.window.firstResponder == webView_) [container_.window makeFirstResponder:container_.stage];
}

bool WebPanel::isVisible() const { return container_.panelVisible; }

void WebPanel::setCollapsed(bool collapsed) {
    container_.collapsed = collapsed;
    [container_ layoutPanes];
}

bool WebPanel::isCollapsed() const { return container_.collapsed; }

void WebPanel::setWidth(float width) {
    container_.panelWidth = std::isfinite(width) ? width : kDefaultWidth;
    [container_ layoutPanes];
}

float WebPanel::width() const { return (float)container_.panelWidth; }

void WebPanel::captureSnapshot() {
    if (!isVisible()) return;
    [webView_ takeSnapshotWithConfiguration:nil completionHandler:^(NSImage* image, NSError*) {
        snapshot_ = image;
    }];
}

NSView* WebPanel::container() const { return container_; }

NSRect WebPanel::panelFrame() const { return webView_.frame; }
