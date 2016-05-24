//
//  VPAudioManager.m
//  Voicepin Collector
//
//  Created by Marek Lipert on 26/04/15.
//  Copyright (c) 2015 VoicePIN sp. z o.o.
//  All rights reserved.
//

#import "VPAudioManager.h"
@import CoreMotion;
@import AVFoundation;

@interface VPAudioManager()<AVAudioRecorderDelegate, AVAudioPlayerDelegate>

@property(nonatomic, strong) AVAudioRecorder *recorder;
@property(nonatomic, strong) AVAudioRecorder *oldRecorderHandle; /* Because of bugs in AVAudioRecorder */
@property(nonatomic, strong) AVAudioPlayer *player;
@property(nonatomic, strong) AVAudioPlayer *oldPlayerHandle; /* Because of bugs in AVAudioRecorder */
@property(nonatomic, strong) NSDictionary *recorderSettings;

@property(nonatomic, assign) float duration;
@property(nonatomic, strong) NSDate *startTime;
@property(nonatomic, strong) NSDate *lastCall;
@property(nonatomic, assign) float timeElapsed;

@property(nonatomic, weak) NSTimer *progressTimer;

@property(nonatomic, assign) BOOL interrupted;

@property(nonatomic, strong) CMMotionManager *motionManager;

@property(nonatomic, strong) NSMutableArray *motionData;

@property(nonatomic, assign) NSInteger proximityValue;

@end


@implementation VPAudioManager

+ (instancetype) sharedInstance
{
    static VPAudioManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        [self setup];
    }
    return self;
}

#pragma mark - External interface


- (BOOL) playFromFile:(NSURL *)path
{
    if(!self.initialized)
    {
        _error = [NSError errorWithDomain:@"VPAudioManager" code:1 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Manager not initialized", @"")}];
        return NO;
    }

    NSAssert(!self.isRecording,@"Recording is already taking place");
    NSAssert(!self.isPlaying,@"Currently playing sample");
    NSAssert(self.delegate,@"No delegate provided");
    
    NSParameterAssert(path);
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory :AVAudioSessionCategoryPlayback error:&err];
    if(err)
    {
        _error = err;
        return NO;
    }

    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:path
                                                               error:&err];
    self.player.meteringEnabled = YES;
    
    if(err)
    {
        self.player = nil;
        _error = err;
        [self audioPlayerDecodeErrorDidOccur:nil error:err];
        return NO;
    }
    self.player.delegate = self;
    [self.player prepareToPlay];
    self.player.volume = 1;
    [self.player play];
    NSLog(@"duration: %f",self.player.duration);
    [self startProgressWithDuration:self.player.duration];
    return YES;
}

- (void) stop
{
    if(self.isRecording) [self.recorder stop];
    if(self.isPlaying)
    {
        [self.player stop];
        [self audioPlayerDidFinishPlaying:self.player successfully:YES];
    }
    [self endProgress];
}



- (NSURL *)saveDataAsRecording:(NSData *)data
{
    NSURL *url = [self newUrl];
    if(!url) return nil;
    [data writeToURL:url atomically:YES];
    return url;
}

- (NSURL *)recordToFileWithDuration:(float)duration
{
    NSURL *url = [self newUrl];
    if(!url)
    {
        _error = [NSError errorWithDomain:@"VPAudioManager" code:VPAudioManagerErrorCodeCachesDirectoryNotAccessible userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Unable to access Caches directory", @"")}];
        return nil;
    }
    return [self startRecordingSampleWithFile:url duration:duration]?url : nil;
}


- (NSString *)microphoneType
{
    NSDictionary *mapping = @{
                              AVAudioSessionPortBuiltInMic : @"built-in",
                              AVAudioSessionPortCarAudio : @"car",
                              AVAudioSessionPortHeadsetMic: @"headset",
                              AVAudioSessionPortLineIn: @"line-in",
                              AVAudioSessionPortBluetoothHFP: @"bluetooth-HFP",
                              AVAudioSessionPortUSBAudio: @"USB",
                              };
    

    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription* desc = [[route inputs] firstObject];
    
    return mapping[desc.portType] ?: @"unknown";
}

#pragma mark - Setters/Getters

- (BOOL) isPlaying
{
    return self.player != nil;
}

- (BOOL) isRecording
{
    return self.recorder != nil;
}


#pragma mark - Helpers

- (void) proximityChanged: (id) obj
{
    self.proximityValue = [UIDevice currentDevice].proximityState;
}

- (NSURL *) newUrl
{
    NSString *stringPath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)objectAtIndex:0]stringByAppendingPathComponent:@"Recordings"];
    
    NSError *error = nil;
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:stringPath])
        [[NSFileManager defaultManager] createDirectoryAtPath:stringPath withIntermediateDirectories:NO attributes:nil error:&error];
    if(error)
    {
        _error = error;
        return nil;
    }
    
    NSString *fileName = [stringPath stringByAppendingFormat:@"/%@.wav", [[NSUUID new] UUIDString]];
    return [NSURL fileURLWithPath:fileName];
}


- (void) endProgress
{
    if(self.duration <= 0.0001) return;
    
    [self.progressTimer invalidate];
    self.progressTimer = nil;

    self.lastCall = nil;
    self.timeElapsed = 0;
    self.startTime = nil;
    self.duration = 0;
}

- (void) startProgressWithDuration: (float) duration
{
    if(duration <= 0.0001) return;
    NSAssert(!self.progressTimer,@"Already progressing");
    self.timeElapsed = 0;
    self.duration = duration;
    self.startTime = [NSDate date];
    self.lastCall = nil;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
    
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    
    self.progressTimer = timer;
}

- (void) updateTimer
{
    float powerLevel = 0.0;
    if(!self.isRecording && !self.isPlaying) return;
    
    NSDate *currentTime = [NSDate date];
    self.timeElapsed += [currentTime timeIntervalSinceDate:self.lastCall?:self.startTime];
    self.lastCall = currentTime;
    
    NSLog(@"Time elapsed: %f",self.timeElapsed);
    
    if(self.isRecording)
    {
        [self.recorder updateMeters];
        powerLevel = [self.recorder averagePowerForChannel:0];
        
        CMDeviceMotion *motion = self.motionManager.deviceMotion;
        CMAttitude *attitude = motion.attitude;
        CMAcceleration acceleration = motion.userAcceleration;
        
        NSDictionary *sensorData = @{
                            @"accelerometer_x" : @(acceleration.x),
                            @"accelerometer_y" : @(acceleration.y),
                            @"accelerometer_z" : @(acceleration.z),
                            
                            @"gyroscope_x" : @(attitude.yaw),
                            @"gyroscope_y" : @(attitude.pitch),
                            @"gyroscope_z" : @(attitude.roll),
                            
                            @"proximity_sensor": @(self.proximityValue),
                            @"time_shift" : @(self.timeElapsed)
                            };
        if(motion) [self.motionData addObject:sensorData];
    }
    if(self.isPlaying)
    {
        [self.player updateMeters];
        powerLevel = [self.player averagePowerForChannel:0];
    }
    
    
    if([self.delegate respondsToSelector:@selector(audioManager:operationProgress:powerLevel:)])
        [self.delegate audioManager:self operationProgress:self.timeElapsed / self.duration powerLevel:powerLevel];
    

    
    if(self.timeElapsed / self.duration >= 1.0)
    {
        if(self.isRecording) [self audioRecorderDidFinishRecording:self.recorder successfully:YES];
        if(self.isPlaying)   [self audioPlayerDidFinishPlaying:self.player successfully:YES];
    }
}

- (void) setup
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proximityChanged:) name:UIDeviceProximityStateDidChangeNotification object:nil];
    
    self.motionManager = [[CMMotionManager alloc] init];
    [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXTrueNorthZVertical];
    
    [audioSession requestRecordPermission:^(BOOL granted)
    {
        NSError *err = nil;
        [audioSession setCategory :AVAudioSessionCategoryPlayAndRecord error:&err];
        if(err)
        {
            _error = err;
            return;
        }
        
        [audioSession setActive:YES error:&err];
        
        if(err)
        {
            _error = err;
            return;
        }
        
        self.recorderSettings = @{
                                  AVSampleRateKey : @(8000.0),
                                  AVFormatIDKey:@(kAudioFormatLinearPCM),
                                  AVLinearPCMBitDepthKey: @(16),
                                  AVNumberOfChannelsKey:@1,
                                  AVLinearPCMIsBigEndianKey:@NO,
                                  AVLinearPCMIsFloatKey:@NO,
                                  AVEncoderAudioQualityKey:@(AVAudioQualityMax)
                                  };
        _initialized = YES;
    }];
    
}

- (BOOL) startRecordingSampleWithFile: (NSURL *)fileName duration: (float) duration
{
    self.motionData = [NSMutableArray array];
    self.interrupted = NO;
    if(!self.initialized)
    {
        _error = [NSError errorWithDomain:@"VPAudioManager" code:VPAudioManagerErrorCodeNotInitialized userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Manager not initialized", @"")}];
        return NO;
    }
    NSAssert(!self.isRecording,@"Recording is already taking place");
    NSAssert(!self.isPlaying,@"Currently playing sample");
    NSAssert(self.initialized,@"Cannot record when initialization failed");
    NSAssert(self.delegate,@"No delegate provided");
    NSParameterAssert(fileName);
    NSError *error = nil;
    
    [[AVAudioSession sharedInstance] setCategory :AVAudioSessionCategoryRecord error:&error];
    if(error)
    {
        _error = error;
        return NO;
    }

    
    [self startProgressWithDuration:duration];
    self.recorder = [[AVAudioRecorder alloc] initWithURL:fileName settings:self.recorderSettings error:&error];
    if(error)
    {
        _error = error;
        self.recorder = nil;
        [self audioRecorderEncodeErrorDidOccur:nil error:error];
        return NO;
    }
    self.recorder.meteringEnabled = YES;
    self.recorder.delegate = self;
    [self.recorder prepareToRecord];
    self.recorder.meteringEnabled = YES;
    if(duration > 0) [self.recorder recordForDuration:duration];
    else [self.recorder record];
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    return YES;
}


#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    if(!self.isRecording) return;
    if(recorder.isRecording) [recorder stop];
    self.oldRecorderHandle = recorder;
    self.recorder = nil;
    [self endProgress];
    
    NSArray *md = self.motionData.count ? self.motionData : nil;
    self.motionData = nil;
    
    if(!flag)
    {
        _error = [NSError errorWithDomain:@"VPAudioManager" code:VPAudioManagerErrorCodeUnspecificRecordingError userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Error during recording", @"")}];
        [self.delegate audioManager:self didFinishRecordingWithError:_error interrupted:self.interrupted sensorData:md];
        return;
    }
    [self.delegate audioManager:self didFinishRecordingWithError:nil interrupted:self.interrupted sensorData:md];
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error
{
    _error = error;
}

- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder
{
    self.interrupted = YES;
    [self audioRecorderDidFinishRecording:recorder successfully:YES];
}



#pragma mark - AVAudipPlayerDelegate



- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
    [self audioPlayerDidFinishPlaying:player successfully:YES];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    _error = error;
}

-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self endProgress];
    NSLog(@"Finished playing!!!");
    if(self.player.isPlaying) [self.player stop];
    self.oldPlayerHandle = self.player;
    self.player = nil;
    if(!flag)
    {
        _error = [NSError errorWithDomain:@"VPAudioManager" code:VPAudioManagerErrorCodeUnspecificPlaybackError userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Error during playback", @"")}];
        [self.delegate audioManager:self didFinishPlaybackWithError:_error ];
        return;
    }
    [self.delegate audioManager:self didFinishPlaybackWithError:nil ];
}

- (void)initialize
{
    /* Empty, but we did call init on sharedInstance! */
}

@end
