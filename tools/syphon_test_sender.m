// Publishes a test pattern over Syphon for checking Linda Vista Mapper's Syphon input.
// Rows are written the way OpenGL senders produce them (row 0 = bottom of the image), so a
// correct receiver shows: red band on top, blue band at the bottom, green stripe on the LEFT,
// and a white bar sweeping left to right.
//
// usage: syphon_test_sender [seconds]

#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>

#import "Syphon/SyphonServerBase.h"
#import "Syphon/SyphonSubclassing.h"

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 30.0;
        const size_t width = 640, height = 360;
        SyphonServerBase* server = [[SyphonServerBase alloc] initWithName:@"Test Pattern" options:nil];
        NSDictionary* description = server.serverDescription;
        printf("serving \"%s - Test Pattern\" for %.0f s\n",
               [[description objectForKey:@"SyphonServerDescriptionAppNameKey"] UTF8String], seconds);
        fflush(stdout);

        NSDate* end = [NSDate dateWithTimeIntervalSinceNow:seconds];
        for (int frame = 0; end.timeIntervalSinceNow > 0; ++frame) {
            @autoreleasepool {
                IOSurfaceRef surface = [server newSurfaceForWidth:width height:height options:nil];
                if (surface) {
                    IOSurfaceLock(surface, 0, NULL);
                    uint8_t* base = IOSurfaceGetBaseAddress(surface);
                    size_t stride = IOSurfaceGetBytesPerRow(surface);
                    size_t barColumn = (size_t)(frame * 8) % width;
                    for (size_t row = 0; row < height; ++row) {
                        size_t y = height - 1 - row;  // distance from the top of the image
                        for (size_t x = 0; x < width; ++x) {
                            uint8_t r, g, b;
                            if (y < height / 4) {
                                r = 220; g = 40; b = 40;
                            } else if (y >= height * 3 / 4) {
                                r = 40; g = 60; b = 220;
                            } else {
                                r = g = b = (uint8_t)(40 + 150 * x / width);
                            }
                            if (x < width / 16) { r = 30; g = 200; b = 60; }
                            if (x >= barColumn && x < barColumn + 12) { r = g = b = 255; }
                            uint8_t* p = base + row * stride + x * 4;
                            p[0] = b; p[1] = g; p[2] = r; p[3] = 255;
                        }
                    }
                    IOSurfaceUnlock(surface, 0, NULL);
                    CFRelease(surface);
                    [server publish];
                }
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 30.0]];
        }
        [server stop];
    }
    return 0;
}
