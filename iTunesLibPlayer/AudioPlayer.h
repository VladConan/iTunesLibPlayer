//
//  AudioPlayer.h
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 09.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AudioEngine.h"
extern NSString* const kAudioPlayerNextTrackNotification;
typedef NS_ENUM(NSUInteger, kAudioPlayerState) {
    kAudioPlayerStateStopped,
    kAudioPlayerStatePlaying,
    kAudioPlayerStatePaused,
    kAudioPlayerStateUnknown
};
@class AudioTrack;
@interface AudioPlayer : NSObject <AudioEngineDelegate>
+(instancetype) sharedPlayer;
/// AVAsset items
@property (nonatomic,copy) NSArray* playList;
@property (nonatomic,copy) NSString* playListName;
@property (nonatomic) NSInteger songIndex;
@property (nonatomic,readonly) AudioTrack* currentTrack;
@property (nonatomic,readonly, getter=getState) kAudioPlayerState state;
@property (nonatomic,getter=getPosition) double position;
@property (nonatomic,readonly) NSTimeInterval duration;
@property (nonatomic) BOOL shuffle;
@property (nonatomic) BOOL repeat;
@property (nonatomic,readonly,getter=isPlaying) BOOL isPlaying;
/// actions
-(kAudioPlayerState) play;
-(kAudioPlayerState) pause;
-(kAudioPlayerState) nextTrack;
-(kAudioPlayerState) prevTrack;
-(kAudioPlayerState) stop;

-(NSArray*) loadITunesTracks;
-(NSArray*) loadLocalTracks;
@end
@class MPMediaItem;
@interface AudioTrack : NSObject
+(instancetype) trackWithMediaItem:(MPMediaItem*) mediaItem;
+(instancetype) trackWithFileName:(NSString*) fileName;
@property (nonatomic,readonly) MPMediaItem* mediaItem;
@property (nonatomic,readonly) NSString* filePath;
@property(nonatomic,readonly) NSURL* url;
@property (nonatomic,readonly) NSString* title;
@property (nonatomic,readonly) NSString* artist;
@property (nonatomic,readonly) NSString* album;
@property (nonatomic,readonly, getter=getImage) UIImage* image;
@property (nonatomic,readonly, getter=getSmallImage) UIImage* smallImage;
@end