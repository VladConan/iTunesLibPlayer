//
//  PlayerViewController.m
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 09.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//

#import "PlayerViewController.h"
#import "AudioPlayer.h"
@interface PlayerViewController ()
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *playListLabel;
@property (weak, nonatomic) IBOutlet UIImageView *coverImage;
@property (weak, nonatomic) IBOutlet UILabel *songTitle;
@property (weak, nonatomic) IBOutlet UILabel *artistTitle;
@property (weak, nonatomic) IBOutlet UILabel *timeFromBegin;
@property (weak, nonatomic) IBOutlet UILabel *timeLasts;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property (weak, nonatomic) IBOutlet UIButton *shuffleButton;
@property (weak, nonatomic) IBOutlet UIButton *prevButton;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *nextButton;
@property (weak, nonatomic) IBOutlet UIButton *repeatButton;
@property (assign,nonatomic) AudioPlayer* player;
@property (nonatomic,strong) NSTimer* progressUpdateTimer;
@end

@implementation PlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.player = [AudioPlayer sharedPlayer];
    // Do any additional setup after loading the view.
}
-(void) viewWillAppear:(BOOL)animated{
    [self updateInformation];
    self.progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}
-(void) viewDidAppear:(BOOL)animated{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateButtons:) name:kAudioPlayerNextTrackNotification object:nil];

}
-(void) viewDidDisappear:(BOOL)animated{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_progressUpdateTimer invalidate];
    self.progressUpdateTimer=nil;
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)hideAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:^{
       
    }];
}
- (IBAction)shuffleAction:(UIButton*)sender {
    _player.shuffle=!_player.shuffle;
    sender.selected= _player.shuffle;
}
- (IBAction)prevAction:(id)sender {
    [_player prevTrack];
    [self updateInformation];
}
- (IBAction)playAction:(id)sender {
    [_player play];
    [self updateInformation];
}
- (IBAction)nextAction:(id)sender {
    [_player nextTrack];
    [self updateInformation];
}
- (IBAction)repeatAction:(UIButton*)sender {
    _player.repeat = !_player.repeat;
    sender.selected = _player.repeat;
}
-(void) updateInformation{
    _playListLabel.text = _player.currentTrack.artist;
    _songTitle.text = _player.currentTrack.title;
    _artistTitle.text = _player.currentTrack.artist;
    _shuffleButton.selected = _player.shuffle;
    _repeatButton.selected = _player.repeat;
    _playButton.selected= _player.isPlaying;
    if (_coverImage.image!=_player.currentTrack.image){
        [UIView transitionWithView:_coverImage
                          duration:0.2
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                            _coverImage.image = _player.currentTrack.image;
                        } completion:nil];
    }
    if (!_player.shuffle){
        _prevButton.enabled = _player.songIndex!=0;
        if (!_player.repeat)
            _nextButton.enabled = _player.songIndex!=_player.playList.count-1;
        else _nextButton.enabled=YES;
    }
    else {
        _prevButton.enabled = YES;
        _nextButton.enabled = YES;
    }
    
}
- (NSString *)stringFromTimeInterval:(NSTimeInterval)interval {
    NSInteger ti = (NSInteger)interval;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    return [NSString stringWithFormat:@"%2ld:%02ld", (long)minutes, (long)seconds];
}
-(void) updateProgress{
    _progressView.progress = _player.position;
    _timeFromBegin.text = [self stringFromTimeInterval:_player.position*_player.duration];
    _timeLasts.text = [@"-" stringByAppendingString:[self stringFromTimeInterval:(1.-_player.position)*_player.duration]];
}
-(void) updateButtons:(NSNotification*) notification{
    
    [self updateInformation];
    
}
-(BOOL) prefersStatusBarHidden{
    return YES;
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
