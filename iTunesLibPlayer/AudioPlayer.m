//
//  AudioPlayer.m
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 09.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//
#import <MediaPlayer/MediaPlayer.h>
#import "AudioPlayer.h"
#import "Eq.h"
#import "UIImage+Resize.h"
NSString* const kAudioPlayerNextTrackNotification = @"playerNextTrack";
@interface AudioPlayer (){
    kAudioPlayerState _state;
    BOOL fistStart;
}
@end;
@implementation AudioPlayer
+(instancetype) sharedPlayer{
    static AudioPlayer* _player = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _player = [[AudioPlayer alloc] init];
    });
    return _player;
}
-(id) init{
    self = [super init];
    if (self){
        fistStart=YES;
        _state = kAudioPlayerStateUnknown;
        [[AudioEngine sharedEngine] setDelegate:self];
    }
    return self;
}
-(void) registerRemoteControls{
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [commandCenter.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self stop];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self nextTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self prevTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}
- (void)configureNowPlayingInfo
{
    MPNowPlayingInfoCenter* info = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary* newInfo = [NSMutableDictionary dictionary];
    newInfo[MPMediaItemPropertyTitle] = _currentTrack.title;
    newInfo[MPMediaItemPropertyArtist] = _currentTrack.artist;
    newInfo[MPMediaItemPropertyPlaybackDuration] = [NSNumber numberWithDouble:[self duration]];
    newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = [NSNumber numberWithDouble:[self duration]*[self getPosition]];
    newInfo[MPMediaItemPropertyArtwork] = _currentTrack.mediaItem ? _currentTrack.mediaItem.artwork : [[MPMediaItemArtwork alloc] initWithImage:_currentTrack.image];
    info.nowPlayingInfo = newInfo;
}
-(void) setPlayList:(NSArray *)playList{
    _playList=nil;
    _playList = [playList copy];
    self.songIndex = 0;
}
-(void) setSongIndex:(NSInteger) songIndex{
    AudioTrack* oldAsset =_currentTrack;
    if (songIndex<_playList.count){
        _currentTrack = _playList[songIndex];
        _songIndex = songIndex;
    }
    else {
        _songIndex=-1;
        _currentTrack=nil;
    }
    if (_currentTrack && _currentTrack!=oldAsset){
        // load into engine
        [[AudioEngine sharedEngine]  setupReaderWithUrl:_currentTrack.url];
    }
    else if (_currentTrack==nil){
        [[AudioEngine sharedEngine] stopPlayback];
    }
    [self updateDuration];
}
-(void) updateDuration{
    if (_currentTrack){
        _duration = CMTimeGetSeconds([AudioEngine sharedEngine].asset.duration);
    }
    else{
        _duration=0;
    }
}
-(kAudioPlayerState) getState{
    // TODO: state
    return kAudioPlayerStateUnknown;
}
-(BOOL) isPlaying{
    AudioEngine* engine = [AudioEngine sharedEngine];
    if ([engine isPlaying] && engine.paused) return NO;
    
    return [[AudioEngine sharedEngine] isPlaying];
}
-(double) getPosition{
    return [[AudioEngine sharedEngine] playbackPosition];
}
#pragma mark - transport
-(kAudioPlayerState) play{
    if (fistStart) [self registerRemoteControls];
    if (_currentTrack){
        AudioEngine* engine = [AudioEngine sharedEngine];
        if (![engine isPlaying]){
            [engine setupReaderWithUrl:_currentTrack.url];
            [engine playback];
            [self configureNowPlayingInfo];
        }
        else if ([engine isPlaying] && engine.paused){
            [engine playback];
            [self configureNowPlayingInfo];
        }
        else{
            [self pause];
        }
    }
    return [self getState];
}
-(kAudioPlayerState) pause{
    if (_currentTrack){
        AudioEngine* engine = [AudioEngine sharedEngine];
        if ([engine isPlaying]){
            [engine pausePlayback];
        }
    }
    return [self getState];
}
-(kAudioPlayerState) nextTrack{
    if (_playList && _playList.count>1){
        NSUInteger nextIndex;
        if (!_shuffle){
            nextIndex=_songIndex+1;
            if (nextIndex>=_playList.count){
                if (_repeat) nextIndex=0;
                else nextIndex=_songIndex;
            }
        }
        else{
            do{
                nextIndex = ((double) rand() / (double) RAND_MAX)*_playList.count;
            } while (nextIndex==_songIndex);
        }
        [self setNextIndex:nextIndex];
        
    }
    [self sendNextTackNotification];
    return [self getState];
}
-(kAudioPlayerState) prevTrack{
    if (_playList && _playList.count>1){
        NSInteger nextIndex;
        if (!_shuffle){
            nextIndex=_songIndex-1;
            if (nextIndex<0){
                if (_repeat) nextIndex=_playList.count-1;
                else nextIndex=_songIndex;
            }
        }
        else{
            do{
                nextIndex = ((double) rand() / (double) RAND_MAX)*_playList.count;
            } while (nextIndex==_songIndex);
        }
        [self setNextIndex:nextIndex];
        
    }
    [self sendNextTackNotification];
    return [self getState];
}
-(void) setNextIndex:(NSInteger) nextIndex{
    if (nextIndex!=_songIndex){
        // stop
        AudioEngine* engine = [AudioEngine sharedEngine];
        if ([engine isPlaying]){
            [engine stopPlayback];
            [self setSongIndex:nextIndex];
            [engine playback];
        }
        else [self setSongIndex:nextIndex];
    }
}
-(kAudioPlayerState) stop{
    AudioEngine* engine = [AudioEngine sharedEngine];
    if ([engine isPlaying]) [engine stopPlayback];
    return [self getState];
}
#pragma mark - tmp

-(NSArray*) loadITunesTracks{
    MPMediaQuery* mq = [MPMediaQuery songsQuery];
    mq.groupingType = MPMediaGroupingAlbum;
    NSMutableArray* array = [NSMutableArray new];
    for (MPMediaItem* item in mq.items) {
        if ([item valueForProperty:MPMediaItemPropertyAssetURL]!=nil){
            AudioTrack* track  = [AudioTrack trackWithMediaItem:item];
            [array addObject:track];
        }
    }
    self.playList = array;
    return array;
}
-(NSArray*) loadLocalTracks{
    NSArray* extensions = @[@"mp3",@"m4a",@"wav"];
    NSMutableArray* array = [NSMutableArray new];
    NSString* path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSAllDomainsMask, YES) firstObject];
    NSDirectoryEnumerator* direnum = [[NSFileManager defaultManager] enumeratorAtPath:path];
    //[direnum skipDescendants];
    NSString *pathName;
    while (pathName = [direnum nextObject])
    {
        if ([extensions containsObject:[pathName pathExtension]]){
            AudioTrack* track = [AudioTrack trackWithFileName:[path stringByAppendingPathComponent:pathName]];
            [array addObject:track];
        }
    }
    self.playList = array;
    return array;
    
}
#pragma mark - engine delegate
-(void) audioEngine:(AudioEngine*) engine playbackEndedWithURL:(NSURL*) url{
    // next track
   [self nextTrack];
}
-(void) sendNextTackNotification{
    [self configureNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"playerNextTrack"
                                                        object:nil
                                                      userInfo:_currentTrack!=nil ? @{@"track" : _currentTrack } : nil];
    
}
@end
#pragma mark - AudioTrack
@interface AudioTrack ()
@property(nonatomic,strong) NSURL* url;
@property (nonatomic,strong) MPMediaItem* mediaItem;
@property (nonatomic,strong) NSString* filePath;
@property (nonatomic,strong) NSString* title;
@property (nonatomic,strong) NSString* artist;
@property (nonatomic,strong) NSString* album;
@property (nonatomic,strong) UIImage* image;
@property (nonatomic,strong) UIImage* smallImage;
@end
@implementation AudioTrack
-(instancetype) initWithMediaItem:(MPMediaItem*) mediaItem{
    if (!mediaItem) return nil;
    self = [super init];
    if (self) {
        self.mediaItem = mediaItem;
        self.title = mediaItem.title;
        self.album = mediaItem.albumTitle;
        self.artist = mediaItem.artist;
        self.url = mediaItem.assetURL;
    }
    return self;
}
-(instancetype) initWithFileName:(NSString*) fileName{
    if (!fileName) return nil;
    self = [super init];
    if (self) {
        self.filePath  = fileName;
        self.title =[[fileName lastPathComponent] stringByDeletingPathExtension];
        // TODO: exstact data from file
        self.album = self.title;
        self.artist = self.title;
        self.url = [NSURL fileURLWithPath:fileName];
    }
    return self;
}
-(UIImage*) getImage{
    if (_image==nil){
        if (_mediaItem)
        _image = [_mediaItem.artwork imageWithSize:CGSizeMake(1024,1024)];
        else if (_filePath){
            // TODO: load image from local file
            _image =  [UIImage imageNamed:@"cover_ph.png"];
        }
    }
    return _image;
}
-(UIImage*) getSmallImage{
    if (!_smallImage){
        if (_mediaItem){
            _smallImage = [_mediaItem.artwork imageWithSize:CGSizeMake(1024,1024)];
        }
        else if (_filePath){
            _smallImage = [self.image resizedImageToSize:CGSizeMake(128, 128)];
        }
    }
    return _smallImage;
}
+(instancetype) trackWithMediaItem:(MPMediaItem*) mediaItem{
    AudioTrack* track = [[AudioTrack alloc] initWithMediaItem:mediaItem];
    return track;
}
+(instancetype) trackWithFileName:(NSString*) fileName{
    AudioTrack* track = [[AudioTrack alloc] initWithFileName:fileName];
    return track;
}









@end
