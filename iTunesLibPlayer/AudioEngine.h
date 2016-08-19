//
//  AudioEngine.h
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 03.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
@class AudioEngine;
@protocol AudioEngineDelegate
@required
-(void) audioEngine:(AudioEngine*) engine playbackEndedWithURL:(NSURL*) url;
@end
@interface AudioEngine : NSObject
+(instancetype) sharedEngine;
- (id)init;
- (BOOL)start;
- (void)stop;
- (void) setupEq:(Float32*) gains;
@property (nonatomic,assign) id<AudioEngineDelegate> delegate;
@property (nonatomic) Float32 gain;
@property (nonatomic,readonly,strong) AVAssetReader* reader;
@property (nonatomic,readonly,strong) AVAsset* asset;
@property (nonatomic,readonly) BOOL paused;
-(BOOL) setupReaderWithUrl:(NSURL*) url;
-(BOOL) setupReaderWithAsset:(AVAsset*) asset;
-(void) playback;
-(void) stopPlayback;
-(void) pausePlayback;
-(void) continuePlayback;
-(BOOL) isPlaying;
-(float) playbackPosition;
@end

@interface PlaybackBuffer : NSObject
{
    @public
    AudioBufferList* _buffer;
    UInt32 numSamples;
    UInt32 position;
    UInt64 trackPosition;
}
-(id) initWithBuffer:(AudioBufferList*) buffer;
@end