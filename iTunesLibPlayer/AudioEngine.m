//
//  AudioEngine.m
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 03.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//

#import "AudioEngine.h"
#import <libkern/OSAtomic.h>
#import <AVFoundation/AVFoundation.h>
#import "Eq.h"
#define SAMPLERATE 44100.
#define NUMCACHEBUFFERS 8

@import UIKit;
@import Accelerate;
#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&result);
        return NO;
    }
    return YES;
}


@interface AudioEngine () {
    AudioUnit _audioUnit;
    Eq8 eq[2];
    UInt32 sessionBufferDuraion; // all in samples
    UInt32 minSamplesAvailable;
    AudioBufferList* outputBuffers[NUMCACHEBUFFERS];
    UInt64 samplesCount;
    UInt64 samplesNumber;
    @public
    NSLock* soundLock;
}
@property (strong, nonatomic) NSTimer *housekeepingTimer;
@property (nonatomic, strong) id observerToken;
@property (nonatomic,readwrite) AVAssetReader* reader;
@property (nonatomic,strong) AVAssetReaderTrackOutput * output;
@property (nonatomic,strong) NSMutableArray* playbackBuffers;
@property (nonatomic,strong) AVAsset* asset;
@end

@implementation AudioEngine
+(instancetype) sharedEngine{
    static AudioEngine* _engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _engine = [[AudioEngine alloc] init];
    });
    return _engine;
}
-(id)init {
    if ( !(self = [super init]) ) return nil;
    self.playbackBuffers = [NSMutableArray arrayWithCapacity:NUMCACHEBUFFERS];
    _gain=1;
    _paused=NO;
    soundLock = [NSLock new];
    [self setup];

    initEq8(&eq[0], SAMPLERATE);
    initEq8(&eq[1], SAMPLERATE);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self teardown];
}
#pragma mark - eq
- (void) setupEq:(Float32*) gains{
    Float32 preset[BAND_NO];
    memcpy(preset, gains, BAND_NO*sizeof(Float32));
    // normalize preset
    Float32 summ = 0 ;
    for (int i=0; i<BAND_NO; i++) {
        summ+=preset[i];
    }
    Float32 norm_value = summ/BAND_NO;
    for (int i=0; i<BAND_NO; i++) {
        preset[i]-=norm_value;
    }
    for (int i=0; i<BAND_NO; i++) {
        SetGainEq8(&eq[0], i, gains[i]);
        SetGainEq8(&eq[1], i, gains[i]);
    }
}
#pragma mark - setup
- (void)setup {
    
    NSError *error = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if ( ![session setCategory:AVAudioSessionCategoryPlayback
                                           withOptions:0
                                                 error:&error] ) {
        NSLog(@"Couldn't set audio session category: %@", error);
    }
    
    if ( ![session setActive:YES error:&error] ) {
        NSLog(@"Couldn't set audio session active: %@", error);
    }
    if (![session setPreferredSampleRate:8192./(double)SAMPLERATE error:&error]){
        NSLog(@"Couldn't set audio session sample rate: %@", error);
    }
    if (![session setPreferredIOBufferDuration:SAMPLERATE error:&error]){
        NSLog(@"Couldn't set audio session sample rate: %@", error);
    }

    // Create the audio unit
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    checkResult(AudioComponentInstanceNew(inputComponent, &_audioUnit), "AudioComponentInstanceNew");
    
    // Set the stream format
    AudioStreamBasicDescription clientFormat = [AudioEngine nonInterleavedFloatStereoAudioDescription];
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &clientFormat, sizeof(clientFormat)),
                "kAudioUnitProperty_StreamFormat");
    
    // Set the render callback
    AURenderCallbackStruct rcbs = { .inputProc = audioUnitRenderCallback, .inputProcRefCon = (__bridge void *)(self) };
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &rcbs, sizeof(rcbs)),
                "kAudioUnitProperty_SetRenderCallback");
    
    UInt32 framesPerSlice = 8192;
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &framesPerSlice, sizeof(framesPerSlice)),
                "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice");
    
    // Initialize the audio unit
    checkResult(AudioUnitInitialize(_audioUnit), "AudioUnitInitialize");
    
    // Watch for session interruptions
    self.observerToken =
    [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        NSInteger type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
        if ( type == AVAudioSessionInterruptionTypeBegan ) {
            [self stop];
        } else {
            if ( ![self start] ) {
                [self teardown];
                [self setup];
                [self start];
            }
        }
    }];
    // buffers
    sessionBufferDuraion  = framesPerSlice;
    minSamplesAvailable = sessionBufferDuraion*(NUMCACHEBUFFERS/2);
    for (int i=0; i<NUMCACHEBUFFERS; i++) {
        outputBuffers[i] = valloc(sizeof(AudioBufferList)+sizeof(AudioBuffer));
        outputBuffers[i]->mNumberBuffers=2;
        UInt32 bytes = sessionBufferDuraion*sizeof(Float32);
        outputBuffers[i]->mBuffers[0].mData = malloc(bytes);
        outputBuffers[i]->mBuffers[0].mDataByteSize = bytes;
        outputBuffers[i]->mBuffers[0].mNumberChannels=1;
        outputBuffers[i]->mBuffers[1].mData = malloc(bytes);
        outputBuffers[i]->mBuffers[2].mDataByteSize = bytes;
        outputBuffers[i]->mBuffers[3].mNumberChannels=1;
    }
}

- (void)teardown {
    if ( self.running ) {
        [self stop];
    }
    if ( _audioUnit ) {
        checkResult(AudioComponentInstanceDispose(_audioUnit), "AudioComponentInstanceDispose");
        _audioUnit = NULL;
    }
    if ( _observerToken ) {
        [[NSNotificationCenter defaultCenter] removeObserver:_observerToken];
        self.observerToken = nil;
    }
    // free buffers
    @synchronized(self)
    {
        for (int i=0; i<NUMCACHEBUFFERS; i++) {
            if (outputBuffers[i]){
                if (outputBuffers[i]->mBuffers[0].mData) free(outputBuffers[i]->mBuffers[0].mData);
                if (outputBuffers[i]->mBuffers[1].mData) free(outputBuffers[i]->mBuffers[1].mData);
                free(outputBuffers[i]);
            }
        }
    }
}

- (BOOL)running {
    Boolean running = false;
    UInt32 size = sizeof(running);
    if ( !checkResult(AudioUnitGetProperty(_audioUnit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &running, &size), "AudioUnitGetProperty") ) {
        return NO;
    }
    
    return running;
}

- (void)stop {
    NSLog(@"Stopping audio engine");
    [_housekeepingTimer invalidate];
    self.housekeepingTimer = nil;
    
    if ( _audioUnit ) {
        checkResult(AudioOutputUnitStop(_audioUnit), "AudioOutputUnitStop");
        [[AVAudioSession sharedInstance] setActive:NO error:NULL];
    }
}

- (BOOL)start {
    NSLog(@"Starting audio engine");
    NSError *error = nil;
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Couldn't activate audio session: %@", error);
        return NO;
    }
    if ( checkResult(AudioOutputUnitStart(_audioUnit), "AudioOutputUnitStart") ) {
        if ( !_housekeepingTimer ) {
            self.housekeepingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                      target:self
                                                                    selector:@selector(cleanUp)
                                                                    userInfo:nil
                                                                     repeats:YES];
        }
        return YES;
    }
    return NO;
}

#pragma mark - Events


-(void)applicationDidEnterBackground:(NSNotification *)notification {

}

-(void)applicationWillEnterForeground:(NSNotification *)notification {

}
#pragma mark - cleanUp
-(void) cleanUp{
    
}
//-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
//
//        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
//}

#pragma mark - Rendering

static OSStatus audioUnitRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    // Use an unretained reference so we don't go retaining stuff in this realtime thread
    __unsafe_unretained AudioEngine *self = (__bridge AudioEngine*)inRefCon;
    
    // Silence buffer
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        vDSP_vclr(ioData->mBuffers[i].mData, 1, inNumberFrames);
    }
    // proccess
    BOOL isEnded = NO;
    [self->soundLock lock]; // lock buffers
        if (self.playbackBuffers.count>0 && !self.paused){
            UInt32 framesLasts = inNumberFrames;
            UInt32 currentPos = 0;
            while (framesLasts>0) {
                PlaybackBuffer* buffer = [self.playbackBuffers firstObject];
                if (buffer){
                    UInt32 fromThisBuffer = buffer->numSamples - buffer->position;
                    if (fromThisBuffer>framesLasts){
                        fromThisBuffer=framesLasts;
                    }
                    Float32* left = buffer->_buffer->mBuffers[0].mData;
                    left+=buffer->position;
                    Float32* right = buffer->_buffer->mBuffers[1].mData;
                    right+=buffer->position;
                    Float32* leftOut = ioData->mBuffers[0].mData;
                    leftOut+=currentPos;
                    Float32* rightOut = ioData->mBuffers[1].mData;
                    rightOut+=currentPos;
                    
                    memcpy(leftOut, left, fromThisBuffer*sizeof(Float32));
                    memcpy(rightOut, right, fromThisBuffer*sizeof(Float32));
                    
                    buffer->position+=fromThisBuffer;
                    if (buffer->position>=buffer->numSamples){
                        [self.playbackBuffers removeObject:buffer];
                    }
                    framesLasts-=fromThisBuffer;
                    currentPos+=fromThisBuffer;
                }
                else break;
            }
            if (self.playbackBuffers.count==0){
                if (self.reader){
                    if (self.reader.status!=AVAssetReaderStatusReading)
                        isEnded=YES;
                }
            }
                
        }
   
    [self->soundLock unlock];
    
    // eq
    runEq8(&(self->eq[0]), ioData->mBuffers[0].mData, ioData->mBuffers[0].mData, inNumberFrames);
    runEq8(&(self->eq[1]), ioData->mBuffers[1].mData, ioData->mBuffers[1].mData, inNumberFrames);
    // vol & clip
    static Float32 p1=1.f;
    static Float32 m1=-1.f;
    float vol = [self gain];
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        vDSP_vsmul(ioData->mBuffers[i].mData, 1, &vol, ioData->mBuffers[i].mData, 1, inNumberFrames);
        vDSP_vclip(ioData->mBuffers[i].mData, 1, &m1, &p1, ioData->mBuffers[i].mData, 1, inNumberFrames);
    }
    if (isEnded){
        if (self.delegate){
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate audioEngine:self playbackEndedWithURL:[((AVURLAsset*)self.reader.asset) URL]];
            });
        }
    }
    return noErr;
}

#pragma mark - Utils

+ (AudioStreamBasicDescription)nonInterleavedFloatStereoAudioDescription {
    AudioStreamBasicDescription audioDescription;
    memset(&audioDescription, 0, sizeof(audioDescription));
    audioDescription.mFormatID          = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags       = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    audioDescription.mChannelsPerFrame  = 2;
    audioDescription.mBytesPerPacket    = sizeof(float);
    audioDescription.mFramesPerPacket   = 1;
    audioDescription.mBytesPerFrame     = sizeof(float);
    audioDescription.mBitsPerChannel    = 8 * sizeof(float);
    audioDescription.mSampleRate        = SAMPLERATE;
    return audioDescription;
}
#pragma mark - Asset
-(BOOL) setupReaderWithUrl:(NSURL*) url{
    AVURLAsset * asset = [[AVURLAsset alloc] initWithURL:url options:nil];
    return [self setupReaderWithAsset:asset];
}
-(BOOL) setupReaderWithAsset:(AVAsset*) asset{
    NSError * error = nil;
    AVAssetReader * reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    samplesCount=0;
    samplesNumber = CMTimeGetSeconds(asset.duration) * SAMPLERATE;
    
    AVAssetTrack * songTrack = [asset.tracks objectAtIndex:0];
    
    
    
    NSDictionary* outputSettingsDict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        
    [NSNumber numberWithInt:kAudioFormatLinearPCM],AVFormatIDKey,
                            @32,AVLinearPCMBitDepthKey,
                            @NO,AVLinearPCMIsBigEndianKey,
                            @YES,AVLinearPCMIsFloatKey,
                            @NO,AVLinearPCMIsNonInterleaved,
                            @44100.,AVSampleRateKey,
                            AVSampleRateConverterAlgorithm_Mastering,AVSampleRateConverterAlgorithmKey,
                                        
                                        nil];
    
    AVAssetReaderTrackOutput * output = [[AVAssetReaderTrackOutput alloc] initWithTrack:songTrack outputSettings:outputSettingsDict];
    [reader addOutput:output];

    if (reader){
        self.output=output;
        self.reader=reader;
        self.asset = asset;
        return YES;
    }
    self.output=nil;
    self.reader=nil;
    self.asset = nil;
    return NO;
}
-(UInt32) samplesAvailable{
    UInt32 available = 0;
    int c=32;
    while (![soundLock tryLock] && c++)
        [NSThread sleepForTimeInterval:((double)sessionBufferDuraion/(double)SAMPLERATE)*0.25]; //waith half buffer duration

        if (self.playbackBuffers.count!=0){
            for (PlaybackBuffer* buffer in _playbackBuffers) {
                available += buffer->numSamples - buffer->position;
            }
        }
    if (c!=0) [soundLock unlock];
    return available;
}
-(void) dataRunner{
    while (_reader.status==AVAssetReaderStatusReading) {
        if ([self samplesAvailable]<minSamplesAvailable){
            if (![self getData]){
                // if no data and not reading exit thread
                if (_reader && _reader.status!=AVAssetReaderStatusReading) return;
            }
        }
        else{
            [NSThread sleepForTimeInterval:(double)sessionBufferDuraion/(double)SAMPLERATE];
        }
    
    }
}
-(BOOL) getData{
    CMSampleBufferRef ref= [_output copyNextSampleBuffer];
    if(ref==NULL)
        return NO;
    //copy data to file
    //read next one
    AudioBufferList audioBufferList;
    CMBlockBufferRef blockBuffer;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(ref, NULL, &audioBufferList, sizeof(audioBufferList), NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
    
    if(blockBuffer==NULL)
    {
        return NO;
    }
    if(audioBufferList.mBuffers[0].mDataByteSize==0)
    {
        return NO;
    }
    // add this buffer to playback
    UInt64 numSamples = audioBufferList.mBuffers[0].mDataByteSize / (audioBufferList.mBuffers[0].mNumberChannels*sizeof(Float32));
    PlaybackBuffer* pbuffer = [[PlaybackBuffer alloc] initWithBuffer:&audioBufferList];
    pbuffer->trackPosition=samplesCount;
    samplesCount+=numSamples;
    
    int c=32;
    while (![soundLock tryLock] && c++)
        [NSThread sleepForTimeInterval:((double)sessionBufferDuraion/(double)SAMPLERATE)*0.25]; //waith half buffer duration

    [self.playbackBuffers addObject:pbuffer];
    if (c!=0) [soundLock unlock];
    CFRelease(blockBuffer);
    CFRelease(ref);
    return YES;
}
#pragma mark - playback
-(void) playback{
    if ([[AVAudioSession sharedInstance] isOtherAudioPlaying]) {
        NSLog(@"Other audio playing");
        return;
    }
    if (_paused){
        _paused=NO;
        [self start];
        return;
    }
    [self start];
    if (_reader && _reader.status==AVAssetReaderStatusUnknown){
        _paused=NO;
        samplesCount=0;
        [_reader startReading];
        NSThread* runner = [[NSThread alloc] initWithTarget:self selector:@selector(dataRunner) object:nil];
        if ([runner respondsToSelector:@selector(setQualityOfService:)])
            [runner setQualityOfService:NSQualityOfServiceUtility];
        else [runner setThreadPriority:0.75];
        [runner start];
    }
}
-(void) stopPlayback{
    if (_reader && _reader.status == AVAssetReaderStatusReading){
        [soundLock lock];
        _paused=NO;
        [_reader cancelReading];
        self.reader=nil;
        self.output=nil;
        [self.playbackBuffers removeAllObjects];
        [soundLock unlock];
        [self stop];
    }
}
-(void) pausePlayback{
    if (!_paused && [self isPlaying]){
        _paused = YES;
        [self stop];
    }
}
-(void) continuePlayback{
    if (_paused && [self isPlaying]){
        _paused=NO;
        [self start];
    }
}
-(BOOL) isPlaying{
    return (self.playbackBuffers.count!=0 || _reader.status==AVAssetReaderStatusReading);
}
-(float) playbackPosition{
    if (![self isPlaying]){
        return 0;
    }
    PlaybackBuffer* currentBuffer = self.playbackBuffers.firstObject;
    if (currentBuffer){
        float pos = (float) (currentBuffer->trackPosition+currentBuffer->position) / (float) samplesNumber;
        return pos;
    }
    
    return 0;
}
@end
@implementation PlaybackBuffer
// input buffers must be float inteleaved
-(id) initWithBuffer:(AudioBufferList*) buffer{
    self = [super init];
    if (self){
        position=0;
        UInt32 bytes = buffer->mBuffers[0].mDataByteSize;
        numSamples = bytes / (buffer->mBuffers[0].mNumberChannels*sizeof(Float32));
        _buffer = valloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
        _buffer->mNumberBuffers=2;
        // add buffers
        UInt32 _bufferSize = numSamples*sizeof(Float32);
        _buffer->mBuffers[0].mData = valloc(_bufferSize);
        _buffer->mBuffers[0].mDataByteSize = _bufferSize;
        _buffer->mBuffers[0].mNumberChannels = 1;
        _buffer->mBuffers[1].mData = valloc(_bufferSize);
        _buffer->mBuffers[1].mDataByteSize = _bufferSize;
        _buffer->mBuffers[1].mNumberChannels = 1;
        // deinterlease and copy
        Float32* outLeft = (Float32*) _buffer->mBuffers[0].mData;
        Float32* outRight = (Float32*) _buffer->mBuffers[1].mData;
        Float32* input = buffer->mBuffers[0].mData;
        SInt32 count = numSamples;
        while (count) {
            *(outLeft++) = *(input++);
            *(outRight++) = *(input++);
            count--;
        }
        
        
    }
    return self;
}
-(void) dealloc{
    if (_buffer){
        if (_buffer->mBuffers[0].mData) free(_buffer->mBuffers[0].mData);
        if (_buffer->mBuffers[0].mData) free(_buffer->mBuffers[1].mData);
        free(_buffer);
    }
}
@end
