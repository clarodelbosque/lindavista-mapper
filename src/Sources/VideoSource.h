#pragma once

#include "BaseSource.h"

@class VMVideoPlayer;

class VideoSource : public BaseSource {
public:
    void setup(AppContext& context) override;
    const char* name() const override { return "Video"; }
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void onActivated() override;
    void onDeactivated() override;
    void update() override;
    void drawImGui() override;
    id<MTLTexture> texture() override;
    bool openPath(const std::string& path) override { return load(path); }
    void drawOverlays(float leftInset) override;
    Status status() const override;

    void togglePlayback();
    void stepFrames(int count);
    void close();
    bool isLoaded() const;
    const std::string& path() const { return path_; }
    bool isPlaying() const;
    int currentFrame() const { return frame_; }
    int totalFrameCount() const;
    void seekToFrame(int frame);

private:
    enum TimeDisplayMode { Time = 0, Frames = 1 };

    bool load(const std::string& path);
    void drawSeekbar(float leftInset);

    VMVideoPlayer* player_ = nil;
    std::string path_;
    bool isWaitingOpen_ = false;
    bool showFailedModal_ = false;
    int frame_ = 0;
    TimeDisplayMode timeDisplayMode_ = Frames;
};
