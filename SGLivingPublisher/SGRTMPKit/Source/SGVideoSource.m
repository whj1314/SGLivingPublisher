//
//  SGVideoSource.m
//  SGLivingPublisher
//
//  Created by iossinger on 16/6/13.
//  Copyright © 2016年 iossinger. All rights reserved.
//

#import "SGVideoSource.h"
#import <AVFoundation/AVFoundation.h>

@interface SGVideoSource ()<AVCaptureVideoDataOutputSampleBufferDelegate>
{
    dispatch_queue_t _videoQueue;
}

@property (nonatomic,strong) AVCaptureSession *session;
@property (nonatomic,strong) AVCaptureDevice *videoDevice;
@property (nonatomic,strong) AVCaptureDeviceInput *vdeoInput;
@property (nonatomic,strong) AVCaptureConnection *videoConnection;
@property (nonatomic,strong) AVCaptureVideoDataOutput *videoDataOutput;

@end


@implementation SGVideoSource
- (void)dealloc{
    NSLog(@"%s",__func__);
}
- (instancetype)init{
    if (self = [super init]) {
        
        [self setVideoCapture];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pauseCameraCapture) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resumeCameraCapture) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

/**
 *  预览
 */
- (AVCaptureVideoPreviewLayer *)preLayer{
    if (_preLayer == nil) {
        _preLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        _preLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    }
    return _preLayer;
}

//视频会话
- (void)setVideoCapture{
    
    NSError *error = nil;
    
    self.session = [[AVCaptureSession alloc] init];
    
    //设置摄像头的分辨率640*480
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        self.session.sessionPreset = AVCaptureSessionPreset640x480;
    }
    
    self.videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    //自动变焦
    if([self.videoDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]){
        if([self.videoDevice lockForConfiguration:nil]){
            self.videoDevice.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
    }
    
    //输入我们初始化一个AVCaptureDeviceInput对象，以创建一个输入数据源，该数据源为捕获会话（session）提供视频数据
    self.vdeoInput = [[AVCaptureDeviceInput alloc] initWithDevice:self.videoDevice error:&error];
    if (error) {
        NSLog(@"输入数据源错误");
    }
    if([self.session canAddInput:self.vdeoInput]){
        [self.session addInput:self.vdeoInput];
    }
    
    //输出设置
    // AVCaptureVideoDataOutput可用于处理从视频中捕获的未经压缩的帧。一个AVCaptureVideoDataOutput实例能处理许多其他多媒体API能处理的视频帧，你可以通过captureOutput:didOutputSampleBuffer:fromConnection:这个委托方法获取帧，使用setSampleBufferDelegate:queue:设置抽样缓存委托和将应用回调的队列。
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange 表示原始数据的格式为YUV420
    NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], kCVPixelBufferPixelFormatTypeKey, nil];
    self.videoDataOutput.videoSettings = settings;
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    
    _videoQueue = dispatch_queue_create("VideoQueue", DISPATCH_QUEUE_SERIAL);
    
    [self.videoDataOutput setSampleBufferDelegate:self queue:_videoQueue];
    
    if([self.session canAddOutput:self.videoDataOutput]){
        [self.session addOutput:self.videoDataOutput];
    }
    
    self.videoConnection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    //设置输出图像的方向
    //采集视频注意点：要设置采集竖屏，否则获取的数据是横屏
    //通过AVCaptureConnection就可以设置
    self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

#pragma mark- ------------------control------------------------
//开始
- (void)startVideoCapture{
    [self.session startRunning];
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
}
//停止
- (void)stopVideoCapture{
    [self.session stopRunning];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

//进入后台暂停
- (void)pauseCameraCapture{
    [self.session stopRunning];
}

- (void)resumeCameraCapture{
    [self.session startRunning];
}

#pragma mark 闪光灯开关——————
- (void)changeFlash {
    //修改前必须先锁定闪光灯
    if (!self.videoDevice) {
        return;
    }
    [self.videoDevice lockForConfiguration:nil];
    //前置摄像头开闪光会卡
    //必须判定是否有闪光灯，否则如果没有闪光灯会崩溃
    if ([self.videoDevice hasFlash]) {
        if (self.videoDevice.flashMode == AVCaptureFlashModeOff) {
            self.videoDevice.flashMode = AVCaptureFlashModeOn;
            self.videoDevice.torchMode = AVCaptureTorchModeOn;
        } else if (self.videoDevice.flashMode == AVCaptureFlashModeOn) {
            self.videoDevice.flashMode = AVCaptureFlashModeOff;
            self.videoDevice.torchMode = AVCaptureTorchModeOff;
        }
    }
}

#pragma mark 摄像头切换——————
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices )
        if ( device.position == position )
            return device;
    return nil;
}
- (void)swapFrontAndBackCameras {
    // Assume the session is already running
    NSArray *inputs = self.session.inputs;
    for ( AVCaptureDeviceInput *input in inputs ) {
        AVCaptureDevice *device = input.device;
        if ( [device hasMediaType:AVMediaTypeVideo] ) {
            AVCaptureDevicePosition position = device.position;
            AVCaptureDevice *newCamera = nil;
            AVCaptureDeviceInput *newInput = nil;
            if (position == AVCaptureDevicePositionFront)
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
            else
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
            newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:nil];
            // beginConfiguration ensures that pending changes are not applied immediately
            [self.session beginConfiguration];
            [self.session removeInput:input];
            [self.session addInput:newInput];
            // Changes take effect once the outermost commitConfiguration is invoked.
            [self.session commitConfiguration];
            break;
        }
    }
}


- (void)setConfig:(SGVideoConfig *)config{
    _config = config;
    NSLog(@"video config is %@",config);
    
    //设置帧速
    NSError *error;
    [self.videoDevice lockForConfiguration:&error];
    
    if (error == nil) {
        NSLog(@"支持的帧速范围是: %@",[self.videoDevice.activeFormat.videoSupportedFrameRateRanges objectAtIndex:0]);
        
        if (self.videoDevice.activeFormat.videoSupportedFrameRateRanges){
            [self.videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, config.fps)];
            [self.videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, config.fps)];
        }
    }
    
    [self.videoDevice unlockForConfiguration];
}

#pragma mark - delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    
//    // 通过sampleBuffer得到图片
//    UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
//
//    CVPixelBufferRef pixelBufferRef = [self pixelBufferFromCGImage:image.CGImage];
    
    
    CVPixelBufferRef pixelBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    if ([self.delegate respondsToSelector:@selector(videoSource:didOutputSampleBuffer:)]) {
        [self.delegate videoSource:self didOutputSampleBuffer:pixelBufferRef];
    }
}
//
//// 把buffer流生成图片
//- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
//{
//    // Get a CMSampleBuffer's Core Video image buffer for the media data
//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    // Lock the base address of the pixel buffer
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    
//    // Get the number of bytes per row for the pixel buffer
//    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
//    
//    // Get the number of bytes per row for the pixel buffer
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
//    // Get the pixel buffer width and height
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);
//    
//    // Create a device-dependent RGB color space
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//    
//    // Create a bitmap graphics context with the sample buffer data
//    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
//                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//    // Create a Quartz image from the pixel data in the bitmap graphics context
//    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
//    // Unlock the pixel buffer
//    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
//    
//    // Free up the context and color space
//    CGContextRelease(context);
//    CGColorSpaceRelease(colorSpace);
//    
//    // Create an image object from the Quartz image
//    //UIImage *image = [UIImage imageWithCGImage:quartzImage];
//    UIImage *image = [UIImage imageWithCGImage:quartzImage scale:1.0f orientation:UIImageOrientationRight];
//    
//    // Release the Quartz image
//    CGImageRelease(quartzImage);
//    
//    return (image);
//}
//
//- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image{
//    
//    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
//                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
//                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
//                             nil];
//    
//    CVPixelBufferRef pxbuffer = NULL;
//    
//    CGFloat frameWidth = CGImageGetWidth(image);
//    CGFloat frameHeight = CGImageGetHeight(image);
//    
//    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
//                                          frameWidth,
//                                          frameHeight,
//                                          kCVPixelFormatType_32ARGB,
//                                          (__bridge CFDictionaryRef) options,
//                                          &pxbuffer);
//    
//    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
//    
//    CVPixelBufferLockBaseAddress(pxbuffer, 0);
//    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
//    NSParameterAssert(pxdata != NULL);
//    
//    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
//    
//    CGContextRef context = CGBitmapContextCreate(pxdata,
//                                                 frameWidth,
//                                                 frameHeight,
//                                                 8,
//                                                 CVPixelBufferGetBytesPerRow(pxbuffer),
//                                                 rgbColorSpace,
//                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
//    NSParameterAssert(context);
//    CGContextConcatCTM(context, CGAffineTransformIdentity);
//    CGContextDrawImage(context, CGRectMake(0,
//                                           0,
//                                           frameWidth,
//                                           frameHeight),
//                       image);
//    CGColorSpaceRelease(rgbColorSpace);
//    CGContextRelease(context);
//    
//    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
//    
//    return pxbuffer;
//}

@end
