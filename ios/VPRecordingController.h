//
//  VPProofOfConceptViewController.h
//  Voicepin Collector
//
//  Created by Marek Lipert on 26/04/15.
//  Copyright (c) 2015 Voicepin. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VPRecordingModel.h"


@interface VPRecordingController : UIViewController

@property(nonatomic, strong) NSString *uid;
@property(nonatomic, strong) NSNumber *gid;

@property(nonatomic, strong) VPRecordingModel *model;
@end
