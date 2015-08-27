//
//  VPAudioManager.h
//  Voicepin Collector
//
//  Created by Marek Lipert on 26/04/15.
//  Copyright (c) 2015 Voicepin. All rights reserved.
//
#import <Foundation/Foundation.h>
@class VPAudioManager;

/* Error codes */

typedef enum VPErrorCode
{
    VPAudioManagerErrorCodeUnkonwn,
    VPAudioManagerErrorCodeNotInitialized,
    VPAudioManagerErrorCodeCachesDirectoryNotAccessible,
    VPAudioManagerErrorCodeUnspecificPlaybackError,
    VPAudioManagerErrorCodeUnspecificRecordingError
}
VPAudioManagerErrorCode;

/** A protocol that notifies the delegate about progress and completion of recording/playback tasks */

@protocol VPAudioManagerProtocol <NSObject>

/** This method is called whenever recording stops. It carries an array of device sensor data 
    collected during recording. The reference frame used has z axis pointing up (against gravity) 
    and x axis pointing to true north. Coordinate system is right-handed:
 
      @{
        @"accelerometer_x" : x component of momentary acceleration (excluding gravity) [m/s^2]
        @"accelerometer_y" : y component of momentary acceleration (excluding gravity) [m/s^2]
        @"accelerometer_z" : z component of momentary acceleration (excluding gravity) [m/s^2]
 
        @"gyroscope_x" : yaw [rad]
        @"gyroscope_y" : pitch [rad]
        @"gyroscope_z" : roll [rad]
 
        @"proximity_sensor": 1 if the device is close to the ear, 0 otherwise
        @"time_shift" : time elapsed [s] from the beginning of the recording
       }
*/

- (void) audioManager: (VPAudioManager *)manager didFinishRecordingWithError: (NSError *)error interrupted: (BOOL) interrupted sensorData: (NSArray *)sensorData;


- (void) audioManager: (VPAudioManager *)manager didFinishPlaybackWithError: (NSError *)error;

@optional

/** This method is called every 50ms and updates information about the recording/playing
  * @param powerLevel Measured in dB and ranges from -160 to 0
  * @param progress [0, 1]
  */

- (void) audioManager:(VPAudioManager *)manager operationProgress: (float) progress powerLevel: (float) powerLevel;

@end

/** A singleton class responsible for managing recording and playing back recorded samples */


@interface VPAudioManager : NSObject

+ (instancetype) sharedInstance;

/// Microphone type
@property (nonatomic, readonly) NSString *microphoneType;

/// Set whenever an error occurs.
@property(nonatomic, readonly) NSError *error;

@property(readonly) BOOL isRecording;
@property(readonly) BOOL isPlaying;
/// Is set after first access to sharedInstance after user allows the app to use microphone.
@property(readonly) BOOL initialized;

/// Delegate object that is notified about the progress of recording/playing.
@property(nonatomic, weak) id<VPAudioManagerProtocol> delegate;

/** Begins recording.
  * @param If the duration is negative, recording takes indefinite time. 
  *        Don't put 0.0 here.
  * @return URL to newly created file (saved in caches directory), or nil if an error occured (see error property)
  */
- (NSURL *) recordToFileWithDuration: (float) duration;

/** 
  * Plays a sound file found in path.
  * @param path Path to the sound file
  * @return YES if playback was successfully started, otherwise NO (and appropirate error is set on error property)
  */

- (BOOL) playFromFile: (NSURL *)path;

/** Helper method that saves NSData containing wav file in caches directory and returns full URL path 
  * @param data NSData object that contains wav data file 
  * @return path to the saved file or nil if an error occured (see error property)
  */

- (NSURL *) saveDataAsRecording: (NSData *) data;

/** 
  *  Stop whatever operation is taking place 
  */

- (void) stop;

/** 
  * Initializes audio manager. Not necessary for operation, you may want to initialize it before use to speed up the first recording though. */

- (void) initialize;



@end
