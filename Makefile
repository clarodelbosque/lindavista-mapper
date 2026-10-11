APP_NAME  := Linda Vista Mapper
EXE_NAME  := LindaVistaMapper
VERSION   := 3.1.0
BUILD     := build
APP       := $(BUILD)/$(APP_NAME).app
ARCHS     ?= arm64
MACOS_MIN ?= 12.0

CC  := clang
CXX := clang++

ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))
BASEFLAGS := $(ARCHFLAGS) -mmacosx-version-min=$(MACOS_MIN) -O2 -g -MMD -MP
INCLUDES  := -Isrc -Isrc/Managers -Isrc/Sources -Ivendor/imgui -Ivendor/imgui/backends -Ivendor/ufbx -Ivendor/syphon
CFLAGS    := $(BASEFLAGS) -std=c11
CXXFLAGS  := $(BASEFLAGS) -std=c++17
OBJCFLAGS := -fobjc-arc
SRC_WARN  := -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers

FRAMEWORKS := -framework Cocoa -framework Metal -framework MetalKit -framework QuartzCore \
              -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework IOSurface \
              -framework ImageIO -framework UniformTypeIdentifiers -framework GameController -framework WebKit

APP_SRC    := $(wildcard src/*.mm src/*.cpp src/Managers/*.mm src/Sources/*.mm)
CORE_SRC   := src/SceneLoader.cpp src/Camera.cpp
IMGUI_SRC  := vendor/imgui/imgui.cpp vendor/imgui/imgui_draw.cpp vendor/imgui/imgui_tables.cpp \
              vendor/imgui/imgui_widgets.cpp vendor/imgui/backends/imgui_impl_metal.mm \
              vendor/imgui/backends/imgui_impl_osx.mm
UFBX_SRC   := vendor/ufbx/ufbx.c
SYPHON_SERVER_SRC := vendor/syphon/Syphon/SyphonServerBase.m vendor/syphon/Syphon/SyphonServerConnectionManager.m
SYPHON_CLIENT_SRC := $(filter-out $(SYPHON_SERVER_SRC),$(wildcard vendor/syphon/Syphon/*.m)) vendor/syphon/Syphon/SyphonDispatch.c

obj = $(patsubst %,$(BUILD)/obj/%.o,$(1))

APP_OBJS := $(call obj,$(APP_SRC) $(IMGUI_SRC) $(UFBX_SRC) $(SYPHON_CLIENT_SRC))

# Web panel (React + shadcn/ui in ui/), built into one self-contained HTML file and baked
# into the app bundle. It's the default UI (--classic-ui falls back to the ImGui sidebar
# at runtime). Building it is a real prerequisite of `app`, so a plain `make` always bakes
# in the current ui/src -- Requires Node.js.
UI_HTML := ui/dist/index.html
UI_SRC  := $(shell find ui/src -type f 2>/dev/null) ui/index.html ui/vite.config.ts ui/package.json

.PHONY: all app run run-web run-classic ui test tools smoke clean
all: app

app: $(BUILD)/.app-stamp

$(BUILD)/$(EXE_NAME): $(APP_OBJS)
	$(CXX) $(ARCHFLAGS) -mmacosx-version-min=$(MACOS_MIN) $^ $(FRAMEWORKS) -o $@

$(BUILD)/.app-stamp: $(BUILD)/$(EXE_NAME) resources/Info.plist resources/LindaVistaMapper.icns $(wildcard resources/data/*) $(UI_HTML)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BUILD)/$(EXE_NAME) "$(APP)/Contents/MacOS/$(EXE_NAME)"
	sed -e 's/@VERSION@/$(VERSION)/g' resources/Info.plist > "$(APP)/Contents/Info.plist"
	cp resources/LindaVistaMapper.icns "$(APP)/Contents/Resources/"
	cp -R resources/data "$(APP)/Contents/Resources/data"
	mkdir -p "$(APP)/Contents/Resources/ui" && cp $(UI_HTML) "$(APP)/Contents/Resources/ui/"
	codesign --force --sign - "$(APP)"
	@touch $@
	@echo "Built $(APP)"

run: app
	open "$(APP)"

ui: $(UI_HTML)
$(UI_HTML): $(UI_SRC) ui/node_modules/.package-lock.json
	cd ui && npm run build
ui/node_modules/.package-lock.json: ui/package.json
	cd ui && npm install
	@touch $@

# --web-ui/--classic-ui are no-ops/overrides now that the web panel is the default and
# always baked in; these targets just spell the intent out.
run-web: app
	open "$(APP)" --args --web-ui

run-classic: app
	open "$(APP)" --args --classic-ui

# Scene loading and camera math tests (no GPU or window needed).
TEST_OBJS := $(call obj,tests/test_main.cpp tests/test_gpu.mm src/Renderer.mm $(CORE_SRC) $(UFBX_SRC))
$(BUILD)/vm_tests: $(TEST_OBJS)
	$(CXX) $(ARCHFLAGS) -mmacosx-version-min=$(MACOS_MIN) $^ -framework Foundation -framework Metal -o $@
test: $(BUILD)/vm_tests
	python3 tools/make_test_scene.py $(BUILD)/test_scene.fbx
	$(BUILD)/vm_tests $(BUILD)/test_scene.fbx

# Development helpers: a Syphon test-pattern sender and a test-movie generator.
SENDER_OBJS := $(call obj,tools/syphon_test_sender.m $(SYPHON_CLIENT_SRC) $(SYPHON_SERVER_SRC))
$(BUILD)/syphon_test_sender: $(SENDER_OBJS)
	$(CC) $(ARCHFLAGS) -mmacosx-version-min=$(MACOS_MIN) $^ -framework Cocoa -framework IOSurface -framework Metal -o $@
$(BUILD)/make_test_movie: $(call obj,tools/make_test_movie.m)
	$(CC) $(ARCHFLAGS) -mmacosx-version-min=$(MACOS_MIN) $^ -framework Cocoa -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreText -o $@
tools: $(BUILD)/syphon_test_sender $(BUILD)/make_test_movie

# End-to-end checks with the real app (opens its window briefly several times).
smoke: app tools
	python3 tools/smoke_test.py

clean:
	rm -rf $(BUILD)

# Compile rules. Project sources get warnings; vendored sources compile quietly.
$(BUILD)/obj/src/%: WARN := $(SRC_WARN)
$(BUILD)/obj/tests/%: WARN := $(SRC_WARN)
$(BUILD)/obj/tools/%: WARN := $(SRC_WARN)
$(BUILD)/obj/vendor/%: WARN := -w
$(BUILD)/obj/vendor/syphon/%: EXTRA := -include vendor/syphon/Syphon_Prefix.pch

$(BUILD)/obj/%.cpp.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(WARN) $(EXTRA) -c $< -o $@

$(BUILD)/obj/%.mm.o: %.mm
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(OBJCFLAGS) $(INCLUDES) $(WARN) $(EXTRA) -c $< -o $@

$(BUILD)/obj/%.m.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(OBJCFLAGS) $(INCLUDES) $(WARN) $(EXTRA) -c $< -o $@

$(BUILD)/obj/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(WARN) $(EXTRA) -c $< -o $@

-include $(shell find $(BUILD)/obj -name '*.d' 2>/dev/null)
