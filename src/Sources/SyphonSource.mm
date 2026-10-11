#include "SyphonSource.h"

#include "imgui.h"

#import "Syphon/SyphonMetalClient.h"
#import "Syphon/SyphonServerDirectory.h"

static std::string str(NSString* s) { return s ? std::string(s.UTF8String) : std::string(); }

SyphonSource::~SyphonSource() {
    for (id observer in observers_) [[NSNotificationCenter defaultCenter] removeObserver:observer];
    disconnect();
}

void SyphonSource::setup(AppContext& context) {
    BaseSource::setup(context);
    observers_ = [NSMutableArray array];
    for (NSString* name in @[SyphonServerAnnounceNotification, SyphonServerRetireNotification, SyphonServerUpdateNotification]) {
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification*) { refreshServers(); }];
        [observers_ addObject:observer];
    }
    refreshServers();
}

void SyphonSource::refreshServers() {
    servers_.clear();
    for (NSDictionary* desc in [[SyphonServerDirectory sharedDirectory] servers]) {
        std::string app = str(desc[SyphonServerDescriptionAppNameKey]);
        std::string server = str(desc[SyphonServerDescriptionNameKey]);
        std::string display = server.empty() ? app : app + " - " + server;
        servers_.push_back(Server{display, str(desc[SyphonServerDescriptionUUIDKey]), desc});
    }

    bool connectedStillExists = false;
    for (const Server& s : servers_) connectedStillExists |= s.uuid == connectedUUID_;
    if (client_ && !connectedStillExists) disconnect();

    if (!client_ && !wantedName_.empty()) {
        for (size_t i = 0; i < servers_.size(); ++i) {
            if (servers_[i].displayName == wantedName_) {
                connect(i);
                break;
            }
        }
    }
}

void SyphonSource::connect(size_t index) {
    disconnect();
    const Server& server = servers_[index];
    client_ = [[SyphonMetalClient alloc] initWithServerDescription:server.description
                                                            device:ctx->device
                                                           options:nil
                                                   newFrameHandler:nil];
    connectedUUID_ = server.uuid;
    wantedName_ = server.displayName;
}

BaseSource::Status SyphonSource::status() const {
    if (!connectedUUID_.empty()) return {wantedName_, 2};
    if (!wantedName_.empty()) return {"Waiting for Syphon Sender", 1};
    return {servers_.empty() ? "No Syphon servers running" : "No server selected", 0};
}

void SyphonSource::disconnect() {
    [client_ stop];
    client_ = nil;
    frame_ = nil;
    connectedUUID_.clear();
}

void SyphonSource::update() {
    if (!client_) return;
    if (!client_.isValid) {
        disconnect();
        return;
    }
    if (client_.hasNewFrame) {
        id<MTLTexture> next = [client_ newFrameImage];
        if (next) frame_ = next;
    }
}

std::vector<std::string> SyphonSource::serverNames() const {
    std::vector<std::string> names;
    for (const Server& s : servers_) names.push_back(s.displayName);
    return names;
}

int SyphonSource::connectedIndex() const {
    for (size_t i = 0; i < servers_.size(); ++i) {
        if (servers_[i].uuid == connectedUUID_) return (int)i;
    }
    return -1;
}

void SyphonSource::selectServer(size_t index) {
    if (index < servers_.size()) connect(index);
}

void SyphonSource::drawImGui() {
    int selected = connectedIndex();
    const char* preview = selected >= 0 ? servers_[selected].displayName.c_str()
                          : servers_.empty() ? "(No Server)" : "(Select Server)";
    ImGui::PushItemWidth(-1);
    if (ImGui::BeginCombo("##Server", preview)) {
        for (size_t i = 0; i < servers_.size(); ++i) {
            ImGui::PushID((int)i);
            if (ImGui::Selectable(servers_[i].displayName.c_str(), (int)i == selected)) connect(i);
            ImGui::PopID();
        }
        ImGui::EndCombo();
    }
    ImGui::PopItemWidth();
}

void SyphonSource::loadSettings(Settings& settings) {
    Settings s = settings.child("syphon");
    wantedName_ = s.getString("inputName", "");
    refreshServers();
}

void SyphonSource::saveSettings(Settings& settings) {
    Settings s = settings.child("syphon");
    if (!wantedName_.empty()) s.setString("inputName", wantedName_);
}
