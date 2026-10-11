#include "VideoSource.h"
#include "ImGuiApp.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>

// Looping AVPlayer whose frames are exposed as Metal textures (row 0 = top of the frame).
@interface VMVideoPlayer : NSObject
@property (nonatomic, readonly) BOOL loaded;
@property (nonatomic, readonly) BOOL frameNew;
@property (nonatomic, readonly, nullable) id<MTLTexture> texture;
@property (nonatomic, readonly) double fps;
@property (nonatomic, readonly) int totalFrames;
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (BOOL)loadPath:(NSString*)path;
- (void)close;
- (void)update;
- (BOOL)isPlaying;
- (void)setPaused:(BOOL)paused;
- (double)currentTime;
- (int)currentFrame;
- (void)seekToFrame:(int)frame;
- (void)stepFrames:(int)count;
@end

@implementation VMVideoPlayer {
    CVMetalTextureCacheRef _cache;
    AVPlayer* _player;
    AVPlayerItem* _item;
    AVPlayerItemVideoOutput* _output;
    id _endObserver;
    // Recent frames stay retained so textures still referenced by in-flight GPU work remain valid.
    CVMetalTextureRef _recent[3];
    int _recentIndex;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &_cache);
    return self;
}

- (void)dealloc {
    [self close];
    if (_cache) CFRelease(_cache);
}

static bool waitFor(dispatch_semaphore_t semaphore) {
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0;
}

- (BOOL)loadPath:(NSString*)path {
    [self close];
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
                                            options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);

    __block AVAssetTrack* track = nil;
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack*>* tracks, NSError*) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(done);
    }];
    if (!waitFor(done) || !track) return NO;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [track loadValuesAsynchronouslyForKeys:@[@"nominalFrameRate"] completionHandler:^{ dispatch_semaphore_signal(done); }];
    if (!waitFor(done)) return NO;
    [asset loadValuesAsynchronouslyForKeys:@[@"duration", @"playable"] completionHandler:^{ dispatch_semaphore_signal(done); }];
    if (!waitFor(done) || !asset.playable) return NO;
    float fps = track.nominalFrameRate;
    double duration = CMTimeGetSeconds(asset.duration);
#pragma clang diagnostic pop

    _fps = fps > 0 ? fps : 30.0;
    _totalFrames = std::max(1, (int)llround((std::isfinite(duration) ? duration : 0) * _fps));

    NSDictionary* attributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
    _item = [AVPlayerItem playerItemWithAsset:asset];
    [_item addOutput:_output];
    _player = [AVPlayer playerWithPlayerItem:_item];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

    __weak VMVideoPlayer* weakSelf = self;
    _endObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                     object:_item
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification*) {
        VMVideoPlayer* strongSelf = weakSelf;
        if (strongSelf) [strongSelf->_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }];
    _loaded = YES;
    [_player play];
    return YES;
}

- (void)close {
    if (_endObserver) [[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
    _endObserver = nil;
    [_player pause];
    _player = nil;
    _item = nil;
    _output = nil;
    _texture = nil;
    for (CVMetalTextureRef& t : _recent) {
        if (t) CFRelease(t);
        t = nullptr;
    }
    _loaded = NO;
    _frameNew = NO;
}

- (void)update {
    _frameNew = NO;
    if (!_output) return;
    CMTime time = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if (![_output hasNewPixelBufferForItemTime:time]) return;
    CVPixelBufferRef pixels = [_output copyPixelBufferForItemTime:time itemTimeForDisplay:nil];
    if (!pixels) return;
    CVMetalTextureRef metal = nullptr;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _cache, pixels, nil, MTLPixelFormatBGRA8Unorm,
                                              CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &metal);
    CVPixelBufferRelease(pixels);
    if (!metal) return;
    _recentIndex = (_recentIndex + 1) % 3;
    if (_recent[_recentIndex]) CFRelease(_recent[_recentIndex]);
    _recent[_recentIndex] = metal;
    _texture = CVMetalTextureGetTexture(metal);
    _frameNew = YES;
    CVMetalTextureCacheFlush(_cache, 0);
}

- (BOOL)isPlaying { return _player && _player.rate != 0; }

- (void)setPaused:(BOOL)paused {
    if (paused) [_player pause];
    else [_player play];
}

- (double)currentTime {
    double t = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    return std::isfinite(t) ? std::max(0.0, t) : 0;
}

- (int)currentFrame {
    return std::clamp((int)std::floor(self.currentTime * _fps + 1e-3), 0, std::max(0, _totalFrames - 1));
}

- (void)seekToFrame:(int)frame {
    CMTime t = CMTimeMakeWithSeconds((frame + 0.25) / _fps, 1000000);
    [_player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)stepFrames:(int)count {
    [_player pause];
    [_item stepByCount:count];
}
@end

namespace {
const float kSeekbarWidth = 600.0f;
const float kSeekbarHeight = 41.0f;
const float kSeekbarMargin = 30.0f;
const float kPlayWidth = 30.0f;
const float kTimeWidth = 60.0f;
}

void VideoSource::setup(AppContext& context) {
    BaseSource::setup(context);
    player_ = [[VMVideoPlayer alloc] initWithDevice:ctx->device];
}

id<MTLTexture> VideoSource::texture() { return player_.loaded ? player_.texture : nil; }

bool VideoSource::load(const std::string& path) {
    isWaitingOpen_ = false;
    if (path.empty() || ![player_ loadPath:@(path.c_str())]) return false;
    path_ = path;
    frame_ = 0;
    return true;
}

void VideoSource::onActivated() {
    if (isWaitingOpen_) load(path_);
}

void VideoSource::onDeactivated() { [player_ setPaused:YES]; }

void VideoSource::update() {
    [player_ update];
    if (player_.frameNew) frame_ = [player_ currentFrame];
}

void VideoSource::togglePlayback() {
    if (player_.loaded) [player_ setPaused:[player_ isPlaying]];
}

void VideoSource::stepFrames(int count) {
    if (player_.loaded) [player_ stepFrames:count];
}

void VideoSource::close() {
    [player_ close];
    isWaitingOpen_ = false;
    path_.clear();
}

bool VideoSource::isLoaded() const { return player_.loaded; }

bool VideoSource::isPlaying() const { return player_.loaded && [player_ isPlaying]; }

int VideoSource::totalFrameCount() const { return player_.loaded ? player_.totalFrames : 0; }

void VideoSource::seekToFrame(int frame) {
    if (!player_.loaded) return;
    frame_ = std::clamp(frame, 0, player_.totalFrames - 1);
    [player_ setPaused:YES];
    [player_ seekToFrame:frame_];
}

void VideoSource::drawImGui() {
    if (ImGui::Button("Load Video")) {
        ctx->runLater([this] {
            std::string path = Dialogs::chooseFile("Load Video File");
            if (!path.empty() && !load(path)) showFailedModal_ = true;
        });
    }
    ImGui::SameLine();
    ImGui::TextUnformatted(player_.loaded ? path_.c_str() : "(No Source)");
    if (ImGui::Button("Close")) close();
    drawOverlays(ImGui::GetWindowSize().x);

    ImGui::Alert("Unknown Video Format", "Failed to load the video as texture.", &showFailedModal_);
}

void VideoSource::drawOverlays(float leftInset) {
    if (player_.loaded) drawSeekbar(leftInset);
}

BaseSource::Status VideoSource::status() const {
    if (!player_.loaded) return {"No video loaded", 0};
    return {[@(path_.c_str()) lastPathComponent].UTF8String, 2};
}

void VideoSource::drawSeekbar(float leftInset) {
    ImVec2 display = ImGui::GetIO().DisplaySize;
    float guiWidth = leftInset;
    float width = std::min(display.x - guiWidth - kSeekbarMargin * 2, kSeekbarWidth);
    if (width < kPlayWidth + kTimeWidth + 40) return;

    ImGui::SetNextWindowPos(ImVec2((guiWidth + display.x) / 2 - width / 2, display.y - kSeekbarHeight - kSeekbarMargin));
    ImGui::SetNextWindowSize(ImVec2(width, kSeekbarHeight));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 2);
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(16, ImGui::GetStyle().ItemSpacing.y));
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.13f, 0.14f, 0.17f, 0.5f));
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
    ImGui::Begin("##Seekbar", nullptr, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize |
                                       ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoSavedSettings);

    bool playing = [player_ isPlaying];
    if (ImGui::PlayToggle("###PlayToggle", &playing, ImVec2(kPlayWidth, -1))) [player_ setPaused:!playing];

    ImGui::SameLine();
    if (ImGui::Seekbar("###Seekbar", &frame_, 0, player_.totalFrames - 1, ImVec2(-kTimeWidth, -1))) {
        [player_ setPaused:YES];
        [player_ seekToFrame:frame_];
    }

    char label[64];
    if (timeDisplayMode_ == Frames) {
        snprintf(label, sizeof(label), "%dF###TimeDisplay", frame_);
    } else {
        int seconds = (int)[player_ currentTime];
        snprintf(label, sizeof(label), "%02d:%02d###TimeDisplay", seconds / 60, seconds % 60);
    }
    ImGui::SameLine();
    if (ImGui::Button(label, ImVec2(-1, -1))) timeDisplayMode_ = timeDisplayMode_ == Time ? Frames : Time;

    ImGui::End();
    ImGui::PopStyleColor(2);
    ImGui::PopStyleVar(2);
}

void VideoSource::loadSettings(Settings& settings) {
    Settings s = settings.child("video");
    path_ = s.getString("path", "");
    isWaitingOpen_ = !path_.empty();
    timeDisplayMode_ = s.getInt("timeDisplayMode", timeDisplayMode_) == Time ? Time : Frames;
}

void VideoSource::saveSettings(Settings& settings) {
    Settings s = settings.child("video");
    if (player_.loaded || isWaitingOpen_) s.setString("path", path_);
    s.setInt("timeDisplayMode", timeDisplayMode_);
}
