#pragma once

#include "BaseSource.h"

class ImageSource : public BaseSource {
public:
    const char* name() const override { return "Image"; }
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void drawImGui() override;
    id<MTLTexture> texture() override { return texture_; }
    bool openPath(const std::string& path) override { return load(path); }
    Status status() const override;
    bool isLoaded() const { return texture_ != nil; }
    const std::string& path() const { return path_; }

private:
    bool load(const std::string& path);

    std::string path_;
    id<MTLTexture> texture_ = nil;
    bool showFailedModal_ = false;
};

// Decodes any ImageIO-supported file into an sRGB RGBA8 texture (row 0 = top of the image).
id<MTLTexture> loadImageTexture(id<MTLDevice> device, const std::string& path);
