#include "ImageSource.h"
#include "ImGuiApp.h"

#import <ImageIO/ImageIO.h>

#include <algorithm>
#include <vector>

id<MTLTexture> loadImageTexture(id<MTLDevice> device, const std::string& path) {
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (!image) return nil;

    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSUInteger maxSize = 16384;
    if (width == 0 || height == 0 || width > maxSize || height > maxSize) {
        CGImageRelease(image);
        return nil;
    }

    std::vector<uint8_t> pixels(width * height * 4);
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(pixels.data(), width, height, 8, width * 4, srgb,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(srgb);
    if (!bitmap) {
        CGImageRelease(image);
        return nil;
    }
    CGContextSetBlendMode(bitmap, kCGBlendModeCopy);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image);
    CGContextRelease(bitmap);
    CGImageRelease(image);

    // Undo premultiplication so transparent screens blend like straight-alpha textures.
    for (size_t i = 0; i < pixels.size(); i += 4) {
        uint8_t a = pixels[i + 3];
        if (a != 0 && a != 255) {
            for (int c = 0; c < 3; ++c) pixels[i + c] = (uint8_t)std::min(255, (pixels[i + c] * 255 + a / 2) / a);
        }
    }

    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                    width:width
                                                                                   height:height
                                                                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeManaged;
    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:width * 4];
    return texture;
}

bool ImageSource::load(const std::string& path) {
    if (path.empty()) return false;
    id<MTLTexture> texture = loadImageTexture(ctx->device, path);
    if (!texture) return false;
    texture_ = texture;
    path_ = path;
    return true;
}

void ImageSource::drawImGui() {
    if (ImGui::Button("Load Image")) {
        ctx->runLater([this] {
            std::string path = Dialogs::chooseFile("Load Image File");
            if (!path.empty() && !load(path)) showFailedModal_ = true;
        });
    }
    ImGui::SameLine();
    ImGui::TextUnformatted(texture_ ? path_.c_str() : "(No Image)");

    ImGui::Alert("Unknown Image Format", "Failed to load the image as texture.", &showFailedModal_);
}

BaseSource::Status ImageSource::status() const {
    if (!texture_) return {"No image loaded", 0};
    return {[@(path_.c_str()) lastPathComponent].UTF8String, 2};
}

void ImageSource::loadSettings(Settings& settings) {
    load(settings.child("image").getString("path", ""));
}

void ImageSource::saveSettings(Settings& settings) {
    Settings s = settings.child("image");
    if (texture_) s.setString("path", path_);
}
