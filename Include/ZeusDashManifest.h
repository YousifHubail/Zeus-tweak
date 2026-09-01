#import <Foundation/Foundation.h>

@class NSURL;

NS_ASSUME_NONNULL_BEGIN

@interface ZeusDashVideoQuality : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *codecs;
@property (nonatomic, copy) NSString *codecName;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger quality;
@property (nonatomic, assign) NSUInteger bandwidth;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) unsigned long long estimatedOutputBytes;
- (BOOL)isAV1;
- (NSString *)menuTitleIncludingCodec:(BOOL)includeCodec;
- (NSString *)menuSubtitle;
@end

FOUNDATION_EXPORT NSString *ZeusDashFormatByteCount(unsigned long long bytes);
FOUNDATION_EXPORT NSTimeInterval ZeusDashManifestDuration(NSString * _Nullable manifest);
FOUNDATION_EXPORT NSArray<ZeusDashVideoQuality *> *ZeusDashManifestVideoQualities(NSString * _Nullable manifest, NSTimeInterval fallbackDuration);

FOUNDATION_EXPORT NSString * _Nullable IGDashManifestBestQualityURL(NSString * _Nullable manifest);
FOUNDATION_EXPORT NSString * _Nullable IGDashManifestBestCompatibleURL(NSString * _Nullable manifest);
FOUNDATION_EXPORT NSString * _Nullable IGDashManifestBestAudioURL(NSString * _Nullable manifest);

/** Rename/transcode a DASH audio download so AVFoundation can mux it. */
FOUNDATION_EXPORT NSString * _Nullable ZeusPrepareDashAudioForMerge(NSString *audioPath);

NS_ASSUME_NONNULL_END

/** Saves a finished video into Photos (creation-request path when supported). */
FOUNDATION_EXPORT void ZeusPhotoLibraryImportVideoFromURL(NSURL *fileURL, void (^completion)(BOOL success, NSError *_Nullable error));

/** Re-encode with AVFoundation so Photos will accept the file (AV1 on iOS 17+). */
FOUNDATION_EXPORT BOOL ZeusExportPhotosCompatibleMP4(NSString *videoPath, NSString *audioPath, BOOL hasAudio, NSString *outputPath);
