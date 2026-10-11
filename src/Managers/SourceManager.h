#pragma once

#include "BaseManager.h"
#include "BaseSource.h"

#include <memory>

class ImageSource;
class SyphonSource;
class VideoSource;

class SourceManager : public BaseManager {
public:
    void setup(AppContext& context) override;
    void update() override;
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void drawImGui() override;
    void drawOverlays() override;
    void dragEvent(const std::vector<std::string>& files) override;
    void writePanelState(NSMutableDictionary* state) override;
    bool handlePanelAction(NSString* type, NSDictionary* action) override;

    // Texture to put on the screens and whether its V coordinate must be flipped so that
    // UV (0,0) lands on the bottom-left of the image.
    id<MTLTexture> currentTexture(bool* flipV);

    bool isVideoActive() const;
    void toggleVideoPlayback();
    void stepVideo(int frames);

private:
    void select(int index);

    std::vector<std::unique_ptr<BaseSource>> sources_;
    SyphonSource* syphon_ = nullptr;
    ImageSource* image_ = nullptr;
    VideoSource* video_ = nullptr;
    int selected_ = 0;
    bool isFlipTexture_ = false;
    id<MTLTexture> defaultTexture_ = nil;
};
