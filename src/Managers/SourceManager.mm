#include "SourceManager.h"

#include "ImGuiApp.h"
#include "ImageSource.h"
#include "SyphonSource.h"
#include "VideoSource.h"

#include <algorithm>

void SourceManager::setup(AppContext& context) {
    BaseManager::setup(context);
    auto syphon = std::make_unique<SyphonSource>();
    syphon_ = syphon.get();
    sources_.push_back(std::move(syphon));
    auto image = std::make_unique<ImageSource>();
    image_ = image.get();
    sources_.push_back(std::move(image));
    auto video = std::make_unique<VideoSource>();
    video_ = video.get();
    sources_.push_back(std::move(video));
    for (auto& source : sources_) source->setup(context);

    defaultTexture_ = loadImageTexture(ctx->device, ctx->dataFile("default_tex.png"));
}

void SourceManager::update() { sources_[selected_]->update(); }

void SourceManager::select(int index) {
    if (index == selected_) return;
    sources_[selected_]->onDeactivated();
    selected_ = index;
    sources_[selected_]->onActivated();
}

id<MTLTexture> SourceManager::currentTexture(bool* flipV) {
    BaseSource& source = *sources_[selected_];
    id<MTLTexture> texture = source.texture();
    bool bottomUp = source.isBottomUp();
    if (!texture) {
        texture = defaultTexture_;
        bottomUp = false;
    }
    *flipV = !bottomUp != isFlipTexture_;
    return texture;
}

bool SourceManager::isVideoActive() const { return sources_[selected_].get() == video_; }

void SourceManager::toggleVideoPlayback() {
    if (isVideoActive()) video_->togglePlayback();
}

void SourceManager::stepVideo(int frames) {
    if (isVideoActive()) video_->stepFrames(frames);
}

void SourceManager::drawImGui() {
    ImGui::SetNextItemOpen(isGuiOpened);
    if ((isGuiOpened = ImGui::CollapsingHeader("Source"))) {
        for (int i = 0; i < (int)sources_.size(); ++i) {
            int choice = selected_;
            if (ImGui::RadioButton(sources_[i]->name(), &choice, i)) select(choice);
            if (i < (int)sources_.size() - 1) ImGui::SameLine();
        }
        sources_[selected_]->drawImGui();
        ImGui::Separator();
        ImGui::Checkbox("Flip Texture Vertically", &isFlipTexture_);
        ImGui::Separator();
    }
}

void SourceManager::drawOverlays() { sources_[selected_]->drawOverlays(0); }

void SourceManager::writePanelState(NSMutableDictionary* state) {
    NSMutableArray* names = [NSMutableArray array];
    for (auto& source : sources_) [names addObject:@(source->name())];
    BaseSource::Status status = sources_[selected_]->status();

    NSMutableArray* serverNames = [NSMutableArray array];
    for (const std::string& name : syphon_->serverNames()) [serverNames addObject:@(name.c_str())];

    state[@"source"] = @{
        @"selected": @(selected_),
        @"names": names,
        @"status": @(status.text.c_str()),
        @"level": @(status.level),
        @"flipTexture": @(isFlipTexture_),
        @"syphon": @{
            @"servers": serverNames,
            @"connectedIndex": @(syphon_->connectedIndex()),
        },
        @"image": @{
            @"loaded": @(image_->isLoaded()),
            @"name": image_->isLoaded() ? @(image_->path().c_str()).lastPathComponent : @"",
        },
        @"video": @{
            @"loaded": @(video_->isLoaded()),
            @"name": video_->isLoaded() ? @(video_->path().c_str()).lastPathComponent : @"",
            @"playing": @(video_->isPlaying()),
            @"frame": @(video_->currentFrame()),
            @"totalFrames": @(video_->totalFrameCount()),
        },
    };
}

bool SourceManager::handlePanelAction(NSString* type, NSDictionary* action) {
    if ([type isEqualToString:@"selectSource"]) {
        int index = [action[@"index"] intValue];
        if (index >= 0 && index < (int)sources_.size()) select(index);
        return true;
    }
    if ([type isEqualToString:@"loadImage"]) {
        ctx->runLater([this] {
            std::string path = Dialogs::chooseFile("Load Image File");
            if (!path.empty()) image_->openPath(path);
        });
        return true;
    }
    if ([type isEqualToString:@"loadVideo"]) {
        ctx->runLater([this] {
            std::string path = Dialogs::chooseFile("Load Video File");
            if (!path.empty()) video_->openPath(path);
        });
        return true;
    }
    if ([type isEqualToString:@"closeVideo"]) {
        video_->close();
        return true;
    }
    if ([type isEqualToString:@"toggleVideoPlayback"]) {
        toggleVideoPlayback();
        return true;
    }
    if ([type isEqualToString:@"stepVideo"]) {
        stepVideo([action[@"frames"] intValue]);
        return true;
    }
    if ([type isEqualToString:@"seekVideo"]) {
        video_->seekToFrame([action[@"frame"] intValue]);
        return true;
    }
    if ([type isEqualToString:@"selectSyphonServer"]) {
        syphon_->selectServer([action[@"index"] intValue]);
        return true;
    }
    if ([type isEqualToString:@"setFlipTexture"]) {
        isFlipTexture_ = [action[@"value"] boolValue];
        return true;
    }
    return false;
}

void SourceManager::dragEvent(const std::vector<std::string>& files) {
    if (files.size() != 1) return;
    NSString* ext = [@(files[0].c_str()) pathExtension].lowercaseString;
    if ([ext isEqualToString:@"fbx"]) return;
    for (int i = 0; i < (int)sources_.size(); ++i) {
        if (sources_[i]->openPath(files[0])) {
            select(i);
            break;
        }
    }
}

void SourceManager::loadSettings(Settings& settings) {
    Settings s = settings.child("sources");
    isGuiOpened = s.getBool("isGuiOpened", isGuiOpened);
    selected_ = std::clamp(s.getInt("selected", 0), 0, (int)sources_.size() - 1);
    for (auto& source : sources_) source->loadSettings(s);
    sources_[selected_]->onActivated();
    isFlipTexture_ = s.getBool("isFlipTexture", false);
}

void SourceManager::saveSettings(Settings& settings) {
    Settings s = settings.child("sources");
    s.setBool("isGuiOpened", isGuiOpened);
    s.setInt("selected", selected_);
    for (auto& source : sources_) source->saveSettings(s);
    s.setBool("isFlipTexture", isFlipTexture_);
}
