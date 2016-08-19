//
//  ViewController.m
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 03.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//

#import "ViewController.h"
#import "Eq.h"
#import "AudioPlayer.h"
// EQ presets
#define EQ_NUMBER_PRESETS 4
Float32 eqPreset[EQ_NUMBER_PRESETS+1][BAND_NO] ={
    { 10,8,6,5,4,3,1,0},
    { 0,0,0,0,5,6,7,10},
    { -1,-5,-6,6,0,5,0,7},
    { 8,4,2,0,-1,-3,2,1},
    { 0,0,0,0,0,0,0,0}
};

@import MediaPlayer;
@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic,strong) id lastSelectedTrack;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *localButton;
@property (weak, nonatomic) IBOutlet UIButton *itunesButton;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leftOffset;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *rightOffset;
@property (weak, nonatomic) IBOutlet UIPageControl *pageControl;

@property (nonatomic,assign) AudioPlayer* player;
@property (weak, nonatomic) IBOutlet UILabel *songTitle;

@end

@implementation ViewController

- (void)viewDidLoad {
    self.player = [AudioPlayer sharedPlayer];

    _leftOffset.constant=0;
    _rightOffset.constant=0;
    _pageControl.currentPage=1;
    [super viewDidLoad];
    _trackSource=-1;
    [self setTrackSource:kTrackSourceiTunes];
    

    // Do any additional setup after loading the view, typically from a nib.
}
-(void) viewWillAppear:(BOOL)animated{
    [self updateSongTitleAndTablePos];
}
-(void) updateSongTitleAndTablePos{
    _lastSelectedTrack = _player.currentTrack;
    [_tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:_player.songIndex inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self updateButtons:nil];
}
-(void) viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateButtons:) name:kAudioPlayerNextTrackNotification object:nil];
}
-(void) viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
-(void) setTrackSource:(kTrackSource)trackSource{
    if (_trackSource!=trackSource){
        _itunesButton.selected=NO;
        _localButton.selected=NO;
        switch (trackSource) {
            case kTrackSourceiTunes:
                [_player loadITunesTracks];
                _itunesButton.selected=YES;
                break;
            case kTrackSourceLocal:
                [_player loadLocalTracks];
                _localButton.selected=YES;
                break;
            default:
                break;
        }
        [_tableView reloadData];
    }
    _trackSource=trackSource;
}
// MARK: actions
- (IBAction)selectEq:(UIButton*)sender {
    NSInteger index =  sender.tag-101;
    [self selectPresetNo:index];
}
-(void) selectPresetNo:(NSInteger) index{
    [[AudioEngine sharedEngine] setupEq:eqPreset[index]];
    for (int i=0; i<EQ_NUMBER_PRESETS; i++) {
        [(UIButton*)[self.view viewWithTag:101+i] setSelected:i==index];
    }
}
- (IBAction)resetEq:(id)sender {
    [self selectPresetNo:EQ_NUMBER_PRESETS];
    for (int i=0; i<EQ_NUMBER_PRESETS; i++) {
        [(UIButton*)[self.view viewWithTag:101+i] setSelected:NO];
    }
}
- (IBAction)selectItunes:(id)sender {
    [self setTrackSource:kTrackSourceiTunes];
}
- (IBAction)selectLocal:(id)sender {
    [self setTrackSource:kTrackSourceLocal];
}
- (IBAction)swipeLeft:(UISwipeGestureRecognizer*) sender {
    // to list select
    if (_pageControl.currentPage!=0){
       [self switchToPage:_pageControl.currentPage-1];
    }
}
-(IBAction)swipweRight:(UISwipeGestureRecognizer*)sender{
    // to eq setting
    if (_pageControl.currentPage!=2){
        [self switchToPage:_pageControl.currentPage+1];
    }
}
-(IBAction)pageControlAction:(UIPageControl*)sender{
    [self switchToPage:sender.currentPage];
}
-(void) switchToPage:(NSInteger) page{
    self.view.userInteractionEnabled=NO;
    [UIView animateWithDuration:0.2 animations:^{
        _leftOffset.constant= (page==0 || page==1) ? 0 : 44;
        _rightOffset.constant= (page==2 || page==1) ? 0 : 44;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        
    } completion:^(BOOL finished) {
        self.view.userInteractionEnabled=YES;
        [_pageControl setCurrentPage:page];
    }];
}

- (IBAction)play:(id)sender {
    [_player play];
    [self updateButtons:nil];
}
- (IBAction)pause:(id)sender {
    [_player pause];
}
- (IBAction)stop:(id)sender {
    [_player stop];
}
- (IBAction)prevoisAction:(id)sender {
    [_player prevTrack];
}
- (IBAction)nextAction:(id)sender {
    [_player nextTrack];
}
- (IBAction)showPlayer:(id)sender {
    [self performSegueWithIdentifier:@"showPlayer" sender:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
-(void) configureCell:(UITableViewCell*) cell withMediaItem:(AudioTrack*) item{

    cell.textLabel.text = item.title;
    cell.detailTextLabel.text = item.album;
    cell.imageView.image= item.smallImage;
}

#pragma mark - table
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return _player.playList.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }
    cell.backgroundColor = [UIColor clearColor];
    cell.opaque=NO;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.contentView.opaque=0;
    //cell.textLabel.textColor = [UIColor whiteColor];
    //cell.detailTextLabel.textColor = [UIColor whiteColor];
    UIView *bgColorView = [[UIView alloc] init];
    bgColorView.backgroundColor = [UIColor colorWithWhite:.5 alpha:0.5];
    [cell setSelectedBackgroundView:bgColorView];
    [self configureCell:cell withMediaItem:_player.playList[indexPath.row]];
    return cell;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    id track = _player.currentTrack;
    self.lastSelectedTrack =  _player.playList[indexPath.row];
    [_player stop];
    if (track!=_lastSelectedTrack){
        [_player setSongIndex:indexPath.row];
        [_player play];
    }
    _songTitle.text = _player.currentTrack.title;
    [self updateButtons:nil];
}

-(void) updateButtons:(NSNotification*) notification{
    _playButton.selected = _player.isPlaying;
    _songTitle.text = _player.currentTrack.title;
}
- (BOOL)canPerformUnwindSegueAction:(SEL)action fromViewController:(UIViewController *)fromViewController withSender:(id)sender NS_AVAILABLE_IOS(6_0){
    return YES;
}
- (UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}
@end
