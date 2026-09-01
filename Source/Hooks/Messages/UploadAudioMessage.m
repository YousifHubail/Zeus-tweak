#import "Include/ZeusHelper.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSURL *gZeusSelectedVideoURL;
static CGFloat gZeusSelectedVideoDuration = 0.0;
static BOOL gZeusExportInProgress = NO;
static id gZeusComputedWaveform = nil; // IGDirectAudioWaveform built from selected audio

// Minimal interface for IG's waveform object
@interface IGDirectAudioWaveform : NSObject
- (instancetype)initWithVolumeRecordingInterval:(CGFloat)interval averageVolume:(id)avg;
@property (nonatomic, readonly) CGFloat volumeRecordingInterval;
@property (nonatomic, readonly) NSArray *averageVolume;
@end

// Build an IGDirectAudioWaveform by sampling RMS loudness every `intervalSec` seconds
static id ZeusBuildWaveformFromAudioURL(NSURL *audioURL, CGFloat intervalSec) {
	@autoreleasepool {
		if (!audioURL) return nil;
		
		AVURLAsset *asset = [AVURLAsset URLAssetWithURL:audioURL options:nil];
		dispatch_semaphore_t loadSem = dispatch_semaphore_create(0);
		[asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
			dispatch_semaphore_signal(loadSem);
		}];
		dispatch_semaphore_wait(loadSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)));
		AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
		if (!audioTrack) return nil;
		
		NSError *error = nil;
		AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
		if (error || !reader) {
			NSLog(@"[Zeus] Waveform reader init failed: %@", error);
			return nil;
		}
		
		CMAudioFormatDescriptionRef fmt = (__bridge CMAudioFormatDescriptionRef)audioTrack.formatDescriptions.firstObject;
		const AudioStreamBasicDescription *asbd = fmt ? CMAudioFormatDescriptionGetStreamBasicDescription(fmt) : NULL;
		double sampleRate = asbd ? asbd->mSampleRate : 44100.0;
		uint32_t channels = asbd ? asbd->mChannelsPerFrame : 1;
		if (channels == 0) channels = 1;
		NSUInteger samplesPerBucket = (NSUInteger)MAX(1, llround(sampleRate * intervalSec));
		
		NSDictionary *outputSettings = @{
			AVFormatIDKey: @(kAudioFormatLinearPCM),
			AVLinearPCMIsBigEndianKey: @NO,
			AVLinearPCMIsFloatKey: @NO,
			AVLinearPCMBitDepthKey: @(16),
			AVLinearPCMIsNonInterleaved: @NO
		};
		AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:outputSettings];
		output.alwaysCopiesSampleData = NO;
		[reader addOutput:output];
		[reader startReading];
		
		NSMutableArray *buckets = [NSMutableArray array];
		NSUInteger bucketCount = 0;
		double sumSquares = 0.0;
		
		while (reader.status == AVAssetReaderStatusReading) {
			CMSampleBufferRef sbuf = [output copyNextSampleBuffer];
			if (!sbuf) break;
			
			CMBlockBufferRef bbuf = CMSampleBufferGetDataBuffer(sbuf);
			if (!bbuf) {
				CFRelease(sbuf);
				continue;
			}
			size_t length = CMBlockBufferGetDataLength(bbuf);
			if (length == 0) {
				CFRelease(sbuf);
				continue;
			}
			
			SInt16 *data = (SInt16 *)malloc(length);
			if (!data) {
				CFRelease(sbuf);
				break;
			}
			CMBlockBufferCopyDataBytes(bbuf, 0, length, data);
			
			size_t frames = length / (sizeof(SInt16) * channels);
			for (size_t f = 0; f < frames; f++) {
				double frameAcc = 0.0;
				for (uint32_t ch = 0; ch < channels; ch++) {
					SInt16 s = data[f * channels + ch];
					double v = (double)s / 32768.0; // normalize to [-1, 1]
					frameAcc += v;
				}
				double frameAvg = frameAcc / (double)channels;
				sumSquares += frameAvg * frameAvg;
				bucketCount++;
				
				if (bucketCount >= samplesPerBucket) {
					double rms = sqrt(sumSquares / (double)bucketCount);
					NSString *val = [NSString stringWithFormat:@"%.4f", rms];
					[buckets addObject:val];
					bucketCount = 0;
					sumSquares = 0.0;
				}
			}
			
			free(data);
			CFRelease(sbuf);
		}
		
		// Flush the last partial bucket
		if (bucketCount > 0) {
			double rms = sqrt(sumSquares / (double)bucketCount);
			NSString *val = [NSString stringWithFormat:@"%.4f", rms];
			[buckets addObject:val];
		}
		
		if (reader.status == AVAssetReaderStatusFailed) {
			NSLog(@"[Zeus] Waveform reader failed: %@", reader.error);
		}
		
		Class Waveform = NSClassFromString(@"IGDirectAudioWaveform");
		if (!Waveform) {
			NSLog(@"[Zeus] Waveform class not found");
			return nil;
		}
		
		// Build IG waveform object
		id waveformObj = [[Waveform alloc] initWithVolumeRecordingInterval:intervalSec averageVolume:buckets];
		return waveformObj;
	}
}

// Cached selectors used when invoking original IMPs safely
static inline SEL ZeusStartRecordingSel(void) {
	static SEL s;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		s = @selector(startRecordingWithButtonTapFromEntryPoint:);
	});
	return s;
}

static inline SEL ZeusUploadAudioSel(void) {
	static SEL s;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		s = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:sendButtonTypeTapped:);
	});
	return s;
}

static inline SEL ZeusUploadAudioSelAI(void) {
	static SEL s;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		s = NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:sendButtonTypeTapped:");
	});
	return s;
}

static inline SEL ZeusUploadAudioSelAIType(void) {
	static SEL s;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		s = NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:");
	});
	return s;
}

static void (*orig_voiceMessageButton)(id self, SEL _cmd, NSInteger entryPoint);

@interface ZeusAudioPickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSURL *selectedMediaURL;
@property (nonatomic, weak) id targetVoiceController;
@property (nonatomic, assign) NSInteger savedEntryPoint;
+ (instancetype)shared;
@end

static void hook_voiceMessageButton(id self, SEL _cmd, NSInteger entryPoint) {
	if (!ENABLED(@"Upload Audio Messages")) {
		orig_voiceMessageButton(self, _cmd, entryPoint);
		return;
	}
	
    [ZeusHelper showCustomAlertWithActions:@"✋ Woah! Hold up!" description:@"Do you want to upload an audio message or record a new one?" actions:@[
        @{
            @"title": @"Upload from Camera Roll",
            @"handler": ^(id sender) {
                // Show camera roll picker
				dispatch_async(dispatch_get_main_queue(), ^{
					ZeusAudioPickerDelegate *delegate = [ZeusAudioPickerDelegate shared];
					delegate.targetVoiceController = self;
					delegate.savedEntryPoint = entryPoint;
					UIImagePickerController *picker = [UIImagePickerController new];
					picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
					picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
					picker.delegate = delegate;
					UIViewController *topVC = [ZeusHelper topViewController];
					if (topVC) {
						[topVC presentViewController:picker animated:YES completion:nil];
					} else {
						NSLog(@"[Zeus] Failed to present picker: topViewController is nil");
					}
				});
            }
        },
		@{
			@"title": @"Upload from Files",
			@"handler": ^(id sender) {
				dispatch_async(dispatch_get_main_queue(), ^{
					ZeusAudioPickerDelegate *delegate = [ZeusAudioPickerDelegate shared];
					delegate.targetVoiceController = self;
					delegate.savedEntryPoint = entryPoint;
					NSArray *docTypes = @[ @"public.mpeg-4-audio", @"public.mp3" ];
					UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:docTypes inMode:UIDocumentPickerModeImport];
					picker.delegate = (id<UIDocumentPickerDelegate>)delegate;
					if ([picker respondsToSelector:@selector(setAllowsMultipleSelection:)]) {
						picker.allowsMultipleSelection = NO;
					}
					UIViewController *topVC = [ZeusHelper topViewController];
					if (topVC) {
						[topVC presentViewController:picker animated:YES completion:nil];
					} else {
						NSLog(@"[Zeus] Failed to present document picker: topViewController is nil");
					}
				});
			}
		},
        @{
            @"title": @"Record a new one",
            @"handler": ^(id sender) {
                // Start recording
                orig_voiceMessageButton(self, _cmd, entryPoint);
            }
        },
        @{
            @"title": @"Cancel",
            @"handler": ^(id sender) {
                // Do nothing
            }
        }
    ]];
}

static void (*orig_uploadAudioMessage)(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, NSInteger sendButtonTypeTapped);
static void (*orig_uploadAudioMessage2)(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, id aiVoiceEffectApplied, NSInteger sendButtonTypeTapped);
static void (*orig_uploadAudioMessage3)(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, id aiVoiceEffectApplied, id aiVoiceEffectType, NSInteger sendButtonTypeTapped);

static void ZeusClearPickedAudioState(void) {
	gZeusSelectedVideoURL = nil;
	gZeusSelectedVideoDuration = 0.0;
	gZeusComputedWaveform = nil;
}

// Try sending directly without toggling the microphone UI.
// IG 441+ uses aiVoiceEffectType; never call a NULL orig IMP (that SIGKILLs with pc=0).
static void ZeusDirectSendOnController(id target, NSInteger entryPoint, NSURL *url, id waveform, CGFloat duration, id aiVoiceEffectApplied) {
	if (!target || !url) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		id viewController = nil;
		NSArray<NSString *> *keys = @[ @"voiceRecordViewController", @"_voiceRecordViewController", @"voiceRecordView", @"_voiceRecordView" ];
		for (NSString *k in keys) {
			@try {
				id v = [target valueForKey:k];
				if (v) { viewController = v; break; }
			} @catch (__unused id e) {}
		}
		NSInteger sendButtonType = 0;
		NSLog(@"[Zeus] Directly invoking upload with selected audio (bypassing mic UI).");

		SEL selAIType = ZeusUploadAudioSelAIType();
		SEL selAI = ZeusUploadAudioSelAI();
		SEL selPlain = ZeusUploadAudioSel();
		BOOL sent = NO;

		if (orig_uploadAudioMessage3) {
			orig_uploadAudioMessage3(target, selAIType, viewController, url, waveform, duration, entryPoint, aiVoiceEffectApplied, nil, sendButtonType);
			sent = YES;
		} else if ([target respondsToSelector:selAIType]) {
			((void (*)(id, SEL, id, id, id, CGFloat, NSInteger, id, id, NSInteger))objc_msgSend)(
				target, selAIType, viewController, url, waveform, duration, entryPoint, aiVoiceEffectApplied, nil, sendButtonType);
			sent = YES;
		} else if (orig_uploadAudioMessage2) {
			orig_uploadAudioMessage2(target, selAI, viewController, url, waveform, duration, entryPoint, aiVoiceEffectApplied, sendButtonType);
			sent = YES;
		} else if ([target respondsToSelector:selAI]) {
			((void (*)(id, SEL, id, id, id, CGFloat, NSInteger, id, NSInteger))objc_msgSend)(
				target, selAI, viewController, url, waveform, duration, entryPoint, aiVoiceEffectApplied, sendButtonType);
			sent = YES;
		} else if (orig_uploadAudioMessage) {
			orig_uploadAudioMessage(target, selPlain, viewController, url, waveform, duration, entryPoint, sendButtonType);
			sent = YES;
		} else if ([target respondsToSelector:selPlain]) {
			((void (*)(id, SEL, id, id, id, CGFloat, NSInteger, NSInteger))objc_msgSend)(
				target, selPlain, viewController, url, waveform, duration, entryPoint, sendButtonType);
			sent = YES;
		}

		if (!sent) {
			NSLog(@"[Zeus] No voice-note upload selector on %@", [target class]);
			[ZeusHelper showToastWithTitle:@"Couldn't send"
								  subtitle:@"Instagram's voice upload API changed."
									  icon:[ZeusHelper imageFromEmojiString:@"⚠️" width:300]
								  autoHide:3
								   openURL:nil];
		}
		ZeusClearPickedAudioState();
	});
}

static void hook_uploadAudioMessage(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, NSInteger sendButtonTypeTapped) {
	if (!ENABLED(@"Upload Audio Messages")) {
		if (orig_uploadAudioMessage)
			orig_uploadAudioMessage(self, _cmd, viewController, audioClipURL, waveform, duration, entryPoint, sendButtonTypeTapped);
		return;
	}

    // If we have a saved picked video, prefer it over incoming args
    NSURL *useURL = gZeusSelectedVideoURL ?: audioClipURL;
    CGFloat useDuration = gZeusSelectedVideoDuration > 0.0 ? gZeusSelectedVideoDuration : duration;
	id useWaveform = gZeusComputedWaveform ?: waveform;
    if (gZeusSelectedVideoURL) {
		NSLog(@"[Zeus] Hook using saved picked video: %@ (%.2fs)", gZeusSelectedVideoURL, gZeusSelectedVideoDuration);
    }
	if (orig_uploadAudioMessage)
		orig_uploadAudioMessage(self, _cmd, viewController, useURL, useWaveform, useDuration, entryPoint, sendButtonTypeTapped);
	ZeusClearPickedAudioState();
}

static void hook_uploadAudioMessage2(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, id aiVoiceEffectApplied, NSInteger sendButtonTypeTapped) {
	if (!ENABLED(@"Upload Audio Messages")) {
		if (orig_uploadAudioMessage2)
			orig_uploadAudioMessage2(self, _cmd, viewController, audioClipURL, waveform, duration, entryPoint, aiVoiceEffectApplied, sendButtonTypeTapped);
		return;
	}

    // If we have a saved picked video, prefer it over incoming args
    NSURL *useURL = gZeusSelectedVideoURL ?: audioClipURL;
    CGFloat useDuration = gZeusSelectedVideoDuration > 0.0 ? gZeusSelectedVideoDuration : duration;
	id useWaveform = gZeusComputedWaveform ?: waveform;
    if (gZeusSelectedVideoURL) {
		NSLog(@"[Zeus] Hook using saved picked video: %@ (%.2fs)", gZeusSelectedVideoURL, gZeusSelectedVideoDuration);
    }
	if (orig_uploadAudioMessage2)
		orig_uploadAudioMessage2(self, _cmd, viewController, useURL, useWaveform, useDuration, entryPoint, aiVoiceEffectApplied, sendButtonTypeTapped);
	ZeusClearPickedAudioState();
}

static void hook_uploadAudioMessage3(id self, SEL _cmd, id viewController, id audioClipURL, id waveform, CGFloat duration, NSInteger entryPoint, id aiVoiceEffectApplied, id aiVoiceEffectType, NSInteger sendButtonTypeTapped) {
	if (!ENABLED(@"Upload Audio Messages")) {
		if (orig_uploadAudioMessage3)
			orig_uploadAudioMessage3(self, _cmd, viewController, audioClipURL, waveform, duration, entryPoint, aiVoiceEffectApplied, aiVoiceEffectType, sendButtonTypeTapped);
		return;
	}

	NSURL *useURL = gZeusSelectedVideoURL ?: audioClipURL;
	CGFloat useDuration = gZeusSelectedVideoDuration > 0.0 ? gZeusSelectedVideoDuration : duration;
	id useWaveform = gZeusComputedWaveform ?: waveform;
	if (gZeusSelectedVideoURL) {
		NSLog(@"[Zeus] Hook using saved picked video: %@ (%.2fs)", gZeusSelectedVideoURL, gZeusSelectedVideoDuration);
	}
	if (orig_uploadAudioMessage3)
		orig_uploadAudioMessage3(self, _cmd, viewController, useURL, useWaveform, useDuration, entryPoint, aiVoiceEffectApplied, aiVoiceEffectType, sendButtonTypeTapped);
	ZeusClearPickedAudioState();
}

@implementation ZeusAudioPickerDelegate

+ (instancetype)shared {
	static ZeusAudioPickerDelegate *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [ZeusAudioPickerDelegate new];
	});
	return shared;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
	NSString *mediaType = info[UIImagePickerControllerMediaType];
	NSURL *videoURL = info[UIImagePickerControllerMediaURL];
	self.selectedMediaURL = videoURL;

	if (videoURL) {
		NSLog(@"[Zeus] Selected video. type=%@ url=%@", mediaType, videoURL);
	} else {
		NSLog(@"[Zeus] Selected non-video media. type=%@", mediaType);
	}

	[picker dismissViewControllerAnimated:YES completion:^{
		if (!videoURL) {
			[ZeusHelper showToastWithTitle:@"Selected" subtitle:@"Media picked from library." icon:[ZeusHelper imageFromEmojiString:@"🎵" width:300] autoHide:2 openURL:nil];
			return;
		}

		// Guard against concurrent exports
		if (gZeusExportInProgress) {
			NSLog(@"[Zeus] Export already in progress; ignoring new selection");
			return;
		}
		gZeusExportInProgress = YES;

		// Prepare export of audio track as MP4 (audio-only). Fallback to M4A if needed.
		AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
		CGFloat durationSeconds = asset ? (CGFloat)CMTimeGetSeconds(asset.duration) : 0.0f;
		NSURL *tempDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
		NSString *mp4Name = [NSString stringWithFormat:@"zeus_upload_%@.mp4", [[NSUUID UUID] UUIDString]];
		NSURL *mp4URL = [tempDirURL URLByAppendingPathComponent:mp4Name];
		[[NSFileManager defaultManager] removeItemAtURL:mp4URL error:nil];

		// Build composition with only audio track
		AVMutableComposition *composition = [AVMutableComposition composition];
		NSError *compError = nil;
		AVAssetTrack *audioSrc = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
		if (audioSrc) {
			AVMutableCompositionTrack *audioComp = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
			[audioComp insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofTrack:audioSrc atTime:kCMTimeZero error:&compError];
		}

		AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:(composition ? composition : asset) presetName:AVAssetExportPresetPassthrough];
		exporter.outputURL = mp4URL;
		exporter.outputFileType = AVFileTypeMPEG4;
		exporter.shouldOptimizeForNetworkUse = YES;

		[exporter exportAsynchronouslyWithCompletionHandler:^{
			if (exporter.status == AVAssetExportSessionStatusCompleted) {
				gZeusSelectedVideoURL = mp4URL;
				gZeusSelectedVideoDuration = durationSeconds;
				NSLog(@"[Zeus] Exported audio-only MP4 to %@ (%.2fs)", mp4URL, durationSeconds);
				
				// Build waveform then send directly, bypassing mic UI
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
					id built = ZeusBuildWaveformFromAudioURL(mp4URL, 0.1);
					gZeusComputedWaveform = built;
					id target = self.targetVoiceController;
					if (target) {
						ZeusDirectSendOnController(target, self.savedEntryPoint, mp4URL, built, durationSeconds, nil);
					}
					gZeusExportInProgress = NO;
				});
			} else {
				NSLog(@"[Zeus] MP4 export failed: status=%ld error=%@ — falling back to M4A", (long)exporter.status, exporter.error);
				// Fallback to M4A
				NSString *m4aName = [NSString stringWithFormat:@"zeus_upload_%@.m4a", [[NSUUID UUID] UUIDString]];
				NSURL *m4aURL = [tempDirURL URLByAppendingPathComponent:m4aName];
				[[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];
				AVAssetExportSession *fallback = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
				fallback.outputURL = m4aURL;
				fallback.outputFileType = AVFileTypeAppleM4A;
				fallback.shouldOptimizeForNetworkUse = YES;
				[fallback exportAsynchronouslyWithCompletionHandler:^{
					if (fallback.status == AVAssetExportSessionStatusCompleted) {
						gZeusSelectedVideoURL = m4aURL;
						gZeusSelectedVideoDuration = durationSeconds;
						NSLog(@"[Zeus] Exported audio to M4A %@ (%.2fs)", m4aURL, durationSeconds);
						
						// Build waveform then send directly, bypassing mic UI
						dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
							id built = ZeusBuildWaveformFromAudioURL(m4aURL, 0.1);
							gZeusComputedWaveform = built;
							id target = self.targetVoiceController;
							if (target) {
								ZeusDirectSendOnController(target, self.savedEntryPoint, m4aURL, built, durationSeconds, nil);
							}
							gZeusExportInProgress = NO;
						});
					} else {
						NSLog(@"[Zeus] Audio export fallback failed: status=%ld error=%@", (long)fallback.status, fallback.error);
						gZeusExportInProgress = NO;
					}
				}];
			}
		}];

		[ZeusHelper showToastWithTitle:@"Selected" subtitle:@"Exporting audio..." icon:[ZeusHelper imageFromEmojiString:@"🎵" width:300] autoHide:2 openURL:nil];
	}];
}

@end

// Files picker support (MP3/M4A)
@implementation ZeusAudioPickerDelegate (ZeusFilesPicker)

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *docURL = urls.firstObject;
	if (!docURL) return;
	
	BOOL shouldStop = [docURL startAccessingSecurityScopedResource];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[ZeusHelper showToastWithTitle:@"Selected" subtitle:@"Importing audio..." icon:[ZeusHelper imageFromEmojiString:@"🎵" width:300] autoHide:2 openURL:nil];
	});
	
	// Guard against concurrent exports
	if (gZeusExportInProgress) {
		NSLog(@"[Zeus] Export already in progress; ignoring new Files selection");
		if (shouldStop) [docURL stopAccessingSecurityScopedResource];
		return;
	}
	gZeusExportInProgress = YES;
	
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:docURL options:nil];
	CGFloat durationSeconds = asset ? (CGFloat)CMTimeGetSeconds(asset.duration) : 0.0f;
	NSURL *tempDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
	NSString *m4aName = [NSString stringWithFormat:@"zeus_upload_%@.m4a", [[NSUUID UUID] UUIDString]];
	NSURL *m4aURL = [tempDirURL URLByAppendingPathComponent:m4aName];
	[[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];
	
	// If already m4a, try a simple copy to temp for consistency
	NSString *ext = docURL.pathExtension.lowercaseString;
	if ([ext isEqualToString:@"m4a"]) {
		NSError *copyErr = nil;
		if (![[NSFileManager defaultManager] copyItemAtURL:docURL toURL:m4aURL error:&copyErr]) {
			NSLog(@"[Zeus] Failed to copy m4a from Files: %@", copyErr);
		}
	}
	
	void (^finishWithURL)(NSURL *) = ^(NSURL *finalURL) {
		gZeusSelectedVideoURL = finalURL;
		gZeusSelectedVideoDuration = durationSeconds;
		NSLog(@"[Zeus] Prepared audio from Files %@ (%.2fs)", finalURL, durationSeconds);
		
		// Build waveform then send directly, bypassing mic UI
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			id built = ZeusBuildWaveformFromAudioURL(finalURL, 0.1);
			gZeusComputedWaveform = built;
			id target = self.targetVoiceController;
			if (target) {
				ZeusDirectSendOnController(target, self.savedEntryPoint, finalURL, built, durationSeconds, nil);
			}
			gZeusExportInProgress = NO;
			if (shouldStop) [docURL stopAccessingSecurityScopedResource];
		});
	};
	
	// If we already have an m4a copy, use it
	if ([[NSFileManager defaultManager] fileExistsAtPath:m4aURL.path]) {
		finishWithURL(m4aURL);
		return;
	}
	
	// Export any other audio (e.g., mp3) to m4a
	AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
	exporter.outputURL = m4aURL;
	exporter.outputFileType = AVFileTypeAppleM4A;
	exporter.shouldOptimizeForNetworkUse = YES;
	[exporter exportAsynchronouslyWithCompletionHandler:^{
		if (exporter.status == AVAssetExportSessionStatusCompleted) {
			finishWithURL(m4aURL);
		} else {
			NSLog(@"[Zeus] Files audio export to M4A failed: status=%ld error=%@", (long)exporter.status, exporter.error);
			// As a last resort, try to use original URL directly
			finishWithURL(docURL);
		}
	}];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	// No-op
}

@end

void ZURegisterUploadAudioMessageHooks(void) {
    Class voiceCtl = objc_getClass("IGDirectThreadViewVoiceController");
    if (!voiceCtl) return;

    NullHookMessageIfPresent(voiceCtl, @selector(startRecordingWithButtonTapFromEntryPoint:), (void *)hook_voiceMessageButton, &orig_voiceMessageButton);

    SEL recordSelAIType = ZeusUploadAudioSelAIType();
    SEL recordSelAI = ZeusUploadAudioSelAI();
    SEL recordSelPlain = ZeusUploadAudioSel();
    if (class_getInstanceMethod(voiceCtl, recordSelAIType))
        NullHookMessageIfPresent(voiceCtl, recordSelAIType, (void *)hook_uploadAudioMessage3, &orig_uploadAudioMessage3);
    else if (class_getInstanceMethod(voiceCtl, recordSelAI))
        NullHookMessageIfPresent(voiceCtl, recordSelAI, (void *)hook_uploadAudioMessage2, &orig_uploadAudioMessage2);
    else if (class_getInstanceMethod(voiceCtl, recordSelPlain))
        NullHookMessageIfPresent(voiceCtl, recordSelPlain, (void *)hook_uploadAudioMessage, &orig_uploadAudioMessage);
}