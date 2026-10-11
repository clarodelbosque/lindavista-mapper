// Writes a short H.264 test movie: red band on top, blue band at the bottom, green stripe on the
// left and the frame number in the middle, for checking Linda Vista Mapper's video input.
//
// usage: make_test_movie OUT.mov [frames] [fps]

#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#import <CoreVideo/CoreVideo.h>

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: make_test_movie OUT.mov [frames] [fps]\n");
            return 1;
        }
        NSString* path = @(argv[1]);
        int frames = argc > 2 ? atoi(argv[2]) : 90;
        int fps = argc > 3 ? atoi(argv[3]) : 30;
        const size_t width = 640, height = 360;

        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        NSError* error = nil;
        AVAssetWriter* writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path]
                                                         fileType:AVFileTypeQuickTimeMovie
                                                            error:&error];
        if (!writer) {
            fprintf(stderr, "cannot create writer: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        AVAssetWriterInput* input = [AVAssetWriterInput
            assetWriterInputWithMediaType:AVMediaTypeVideo
                           outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(width),
                                            AVVideoHeightKey: @(height)}];
        AVAssetWriterInputPixelBufferAdaptor* adaptor = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                       sourcePixelBufferAttributes:@{
                                           (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                           (id)kCVPixelBufferWidthKey: @(width),
                                           (id)kCVPixelBufferHeightKey: @(height),
                                       }];
        [writer addInput:input];
        [writer startWriting];
        [writer startSessionAtSourceTime:kCMTimeZero];

        CGColorSpaceRef rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica-Bold"), 120, NULL);
        for (int f = 0; f < frames; ++f) {
            while (!input.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.005];
            CVPixelBufferRef pixels = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixels);
            CVPixelBufferLockBaseAddress(pixels, 0);
            CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixels), width, height, 8,
                                                     CVPixelBufferGetBytesPerRow(pixels), rgb,
                                                     kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            // CoreGraphics' origin is the bottom-left, so the "top" band sits at high y.
            CGContextSetRGBFillColor(ctx, 0.35, 0.35, 0.35, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
            CGContextSetRGBFillColor(ctx, 0.86, 0.16, 0.16, 1);
            CGContextFillRect(ctx, CGRectMake(0, height * 0.75, width, height * 0.25));
            CGContextSetRGBFillColor(ctx, 0.16, 0.24, 0.86, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, width, height * 0.25));
            CGContextSetRGBFillColor(ctx, 0.12, 0.78, 0.24, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, width / 16.0, height));

            NSString* label = [NSString stringWithFormat:@"%d", f];
            NSDictionary* attrs = @{(id)kCTFontAttributeName: (__bridge id)font,
                                    (id)kCTForegroundColorFromContextAttributeName: @YES};
            CTLineRef line = CTLineCreateWithAttributedString(
                (__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:label attributes:attrs]);
            CGRect bounds = CTLineGetImageBounds(line, ctx);
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
            CGContextSetTextPosition(ctx, (width - bounds.size.width) / 2 - bounds.origin.x,
                                     (height - bounds.size.height) / 2 - bounds.origin.y);
            CTLineDraw(line, ctx);
            CFRelease(line);

            CGContextRelease(ctx);
            CVPixelBufferUnlockBaseAddress(pixels, 0);
            [adaptor appendPixelBuffer:pixels withPresentationTime:CMTimeMake(f, fps)];
            CVPixelBufferRelease(pixels);
        }
        CFRelease(font);
        CGColorSpaceRelease(rgb);

        [input markAsFinished];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (writer.status != AVAssetWriterStatusCompleted) {
            fprintf(stderr, "writing failed: %s\n", writer.error.localizedDescription.UTF8String);
            return 1;
        }
        printf("wrote %d frames at %d fps to %s\n", frames, fps, path.UTF8String);
    }
    return 0;
}
