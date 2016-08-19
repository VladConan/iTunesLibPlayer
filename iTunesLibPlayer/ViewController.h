//
//  ViewController.h
//  iTunesLibPlayer
//
//  Created by Vlad Konon on 03.07.15.
//  Copyright (c) 2015 Vlad Konon. All rights reserved.
//

#import <UIKit/UIKit.h>
typedef NS_ENUM(NSUInteger, kTrackSource) {
    kTrackSourceiTunes=0,
    kTrackSourceLocal,
    kTrackSourceNum
};
@interface ViewController : UIViewController <UITableViewDelegate,UITableViewDataSource>

@property (nonatomic) kTrackSource trackSource;
@end

