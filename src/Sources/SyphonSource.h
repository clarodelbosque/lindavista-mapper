#pragma once

#include "BaseSource.h"

#include <vector>

@class SyphonMetalClient;

class SyphonSource : public BaseSource {
public:
    ~SyphonSource() override;

    void setup(AppContext& context) override;
    const char* name() const override { return "Syphon"; }
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void update() override;
    void drawImGui() override;
    id<MTLTexture> texture() override { return frame_; }
    Status status() const override;
    bool isBottomUp() const override { return true; }

    // Server names in list order, and the index of the connected one (-1 if none), for the
    // web panel's server picker.
    std::vector<std::string> serverNames() const;
    int connectedIndex() const;
    void selectServer(size_t index);

private:
    struct Server {
        std::string displayName;
        std::string uuid;
        NSDictionary* description;
    };

    void refreshServers();
    void connect(size_t index);
    void disconnect();

    std::vector<Server> servers_;
    SyphonMetalClient* client_ = nil;
    id<MTLTexture> frame_ = nil;
    std::string connectedUUID_;
    std::string wantedName_;  // restored from settings or kept after the server quits
    NSMutableArray* observers_ = nil;
};
