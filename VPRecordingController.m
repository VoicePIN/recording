//
//  VPProofOfConceptViewController.m
//  Voicepin Collector
//
//  Created by Marek Lipert on 26/04/15.
//  Copyright (c) 2015 Voicepin. All rights reserved.
//

#import "VPRecordingController.h"
#import "VPAudioManager.h"
#import "VPAppDelegate.h"
#import "MLImageCache.h"
#import "MLProgressHud.h"
#import "VPRectIndicatorsView.h"
#import "VPRecorderView.h"
#import "VPRecordingCell.h"

#define DELETE_ALERT 666
#define NEXT_PHRASE_ALERT 500


@interface VPRecordingController () <VPAudioManagerProtocol, UITableViewDataSource, UITableViewDelegate, UIPickerViewDataSource, UIPickerViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate, VPRecordingCellDelegate, UIAlertViewDelegate>

/* Outlets */
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *verticalSpace;

@property (weak, nonatomic) IBOutlet VPRecorderView *recordingView;
@property (weak, nonatomic) IBOutlet VPRectIndicatorsView *signalStrengthIndicator;

@property (weak, nonatomic) IBOutlet UILabel *phraseProgressLabel;

@property (weak, nonatomic) IBOutlet UITextField *phraseTextField;
@property (weak, nonatomic) IBOutlet UILabel *phraseLabel;

@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (weak, nonatomic) IBOutlet UIView *leftBar;
@property (weak, nonatomic) IBOutlet UIView *rightBar;

- (IBAction)recordAction:(id)sender;
- (IBAction)backAction:(id)sender;


@property(nonatomic, strong) UIPickerView *pickerView;

@property (nonatomic, strong) NSURL *currentRecordingURL;

@property (nonatomic, readonly) NSAttributedString *progressString;
@property (nonatomic, readonly) UIImage *screenShot;


@end

@implementation VPRecordingController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.recordingView.percentComplete = @100;
    VPAudioManager *manager = [VPAudioManager sharedInstance];
    manager.delegate = self;
    self.pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0, 50, 100, 150)];
    self.pickerView.dataSource = self;
    self.pickerView.delegate = self;
    self.pickerView.showsSelectionIndicator = YES;
    self.phraseTextField.inputView = self.pickerView;
    [self setSelectedPhrase:nil];
    [self.tableView registerNib:[UINib nibWithNibName:@"VPRecordingCell" bundle:nil] forCellReuseIdentifier:@"recordingCell"];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapTapped:)];
    [self.view addGestureRecognizer:tap];
    tap.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.model updateDataForUid:self.uid gid:self.gid completion:^(NSError *error, BOOL dataUpdated, BOOL currentPhraseNoLongerValid) {
        if(currentPhraseNoLongerValid) [self setSelectedPhrase:nil];
        if(dataUpdated) [self.tableView reloadData];
    }];
    
}


#pragma mark - Helpers


- (NSAttributedString *) progressString
{
    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", @(self.model.recordings.count)] attributes:@{                                                                                                      NSForegroundColorAttributeName: [UIColor colorWithRed:242.0/255.0 green:242.0/255.0 blue:242.0/255.0 alpha:1.0], NSFontAttributeName : [UIFont fontWithName:@"Dosis-Bold" size:21]}];
    
    [str appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@" / %@", self.model.selectedPhrase[@"recordings_needed"]] attributes:@{                                                                                                      NSForegroundColorAttributeName: [UIColor colorWithRed:242.0/255.0 green:242.0/255.0 blue:242.0/255.0 alpha:1.0], NSFontAttributeName : [UIFont fontWithName:@"Dosis-Medium" size:21]}]];
    return str;
}

- (UIImage *) screenShot
{
    UIImage* image = nil;
    UIWindow *mainWindow = [UIApplication sharedApplication].windows[0];
    
    UIGraphicsBeginImageContext(mainWindow.bounds.size);
    {
        [mainWindow.layer renderInContext: UIGraphicsGetCurrentContext()];
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    return image;
}


#pragma mark - Setters/Getters

- (void)setSelectedPhrase:(NSDictionary *)selectedPhrase
{
    self.model.selectedPhrase = selectedPhrase;
    self.phraseProgressLabel.hidden = self.leftBar.hidden = self.rightBar.hidden = self.recordingView.hidden = self.signalStrengthIndicator.hidden = self.phraseLabel.hidden = selectedPhrase == nil;
    
    self.verticalSpace.priority = selectedPhrase == nil ? 999 : 1;

    if(!selectedPhrase)
    {
        self.phraseTextField.text = NSLocalizedString(@"Select phrase",@"");
        [self.tableView reloadData];
    }
    else
    {
        self.phraseTextField.text = selectedPhrase[@"phrase_text"];
        
        self.phraseLabel.text = selectedPhrase[@"phrase_text"];
        self.phraseProgressLabel.attributedText = self.progressString;
        self.recordingView.numberOfElements = [selectedPhrase[@"recordings_needed"] integerValue];
        self.recordingView.numberOfActiveElements = self.model.recordings.count;
        
        
        [self.tableView reloadData];
    }
}



#pragma mark - Actions

- (IBAction)recordAction:(id)sender
{
    if([VPAudioManager sharedInstance].isPlaying) return;
    
    if([VPAudioManager sharedInstance].isRecording)
    {
        [[VPAudioManager sharedInstance] stop];
        return;
    }
    
    if(self.currentRecordingURL) [[NSFileManager defaultManager] removeItemAtURL:self.currentRecordingURL error:nil];
    self.currentRecordingURL = [[VPAudioManager sharedInstance] recordToFileWithDuration:5.0];
    
}

- (IBAction)backAction:(id)sender
{
    [((VPAppDelegate *)[UIApplication sharedApplication].delegate) replaceRootViewControllerWithController:[[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateInitialViewController] animated:YES completion:^{
        
    }];
}

- (IBAction)tapTapped:(id)sender
{
    if([self.phraseTextField isFirstResponder]) [self setSelectedPhrase: [self.pickerView selectedRowInComponent:0] == 0 ? nil : self.model.phrases[[self.pickerView selectedRowInComponent:0]-1]];
    [self.phraseTextField resignFirstResponder];
}


#pragma mark - VPAudioManagerDelegate

- (void)audioManager:(VPAudioManager *)manager didFinishPlaybackWithError:(NSError *)error
{
    [self.signalStrengthIndicator setupWithBars:0 frame: self.signalStrengthIndicator.frame];
    self.recordingView.percentComplete = @100;
    if(error) [[[UIAlertView alloc] initWithTitle: NSLocalizedString(@"Playback error",@"") message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",@"") otherButtonTitles: nil] show];
}

- (void)audioManager:(VPAudioManager *)manager didFinishRecordingWithError:(NSError *)error interrupted:(BOOL)interrupted sensorData:(NSArray *)sensorData
{
    [self.signalStrengthIndicator setupWithBars:0 frame: self.signalStrengthIndicator.frame];
    self.recordingView.percentComplete = @100;
    if(error)
    {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Recording error",@"") message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",@"") otherButtonTitles: nil] show];
        return;
    }

    if(interrupted) return;
    
    NSData *waveData = [[NSFileManager defaultManager] contentsAtPath:self.currentRecordingURL.path];
    NSParameterAssert(waveData);
    [MLProgressHUD showHUDAddedTo:self.view animated:YES];
    __weak typeof(self) weakSelf = self;
    [self.model addRecordingForData:waveData uid:self.uid gid:self.gid completion:^(NSError *error, NSDictionary *recording) {
        [MLProgressHUD hideAllHUDsForView:weakSelf.view animated:YES];
        
        if(!error)
        {
            [[MLImageCache sharedInstance] cacheData:waveData withUrl:[NSURL URLWithString:recording[@"recording_path"]]];

            [weakSelf.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:weakSelf.model.recordings.count-1 inSection:0]] withRowAnimation:UITableViewRowAnimationLeft];
            weakSelf.phraseProgressLabel.attributedText = weakSelf.progressString;
            weakSelf.phraseProgressLabel.hidden = NO;
            weakSelf.recordingView.numberOfElements = [weakSelf.model.selectedPhrase[@"recordings_needed"] integerValue];
            weakSelf.recordingView.numberOfActiveElements = weakSelf.model.recordings.count;

            if([weakSelf.model phraseTrained:weakSelf.model.selectedPhrase])
            {
                
                UIAlertView *av = [[VPAlertView alloc] initWithPhrase:weakSelf.model.selectedPhrase[@"phrase_text"] delegate:weakSelf showsNextPhraseButton:weakSelf.model.untrainedPhrases.count];
                av.tag = NEXT_PHRASE_ALERT;
                [av show];
            }
            
            if(sensorData.count)
            [[VPAPIClient sharedInstance] appendMotionData:sensorData toRecordingWithId:recording[@"id"] completion:^(NSError *error) {
                NSLog(@"Tried to upload sensor data: %@",sensorData);
                NSLog(@"Sensor data updated error: %@",error);
            }];
        }
        else
        {
            [[[VPAlertView alloc] initWithTitle:NSLocalizedString(@"Błąd łączności",@"") message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",@"") otherButtonTitles: nil] show];
        }
        
    }];
}

- (void)audioManager:(VPAudioManager *)manager operationProgress:(float)progress powerLevel:(float)powerLevel
{
    NSAssert(manager.isRecording || manager.isPlaying,@"Progress block called but no playback/recording present");
    self.recordingView.percentComplete = @(progress*100);
    
    NSInteger barNo =  MAX(((powerLevel + 70)/70)*9,1);
    
    [self.signalStrengthIndicator setupWithBars:barNo frame: self.signalStrengthIndicator.frame];
    NSLog(@"progress %f",progress);
}


#pragma mark - UIPickerViewDelegate

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    [self setSelectedPhrase: row == 0 ? nil : self.model.phrases[row-1] ];
    [self.phraseTextField resignFirstResponder];
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return self.model.phrases.count + 1;
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return row == 0 ? NSLocalizedString(@"Select phrase", @"")  :  self.model.phrases[row-1][@"phrase_text"];
}



#pragma mark - UITableViewDataSource


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 45;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.model.recordings.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}




- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    VPRecordingCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"recordingCell"];
    NSDictionary *recording = self.model.recordings[indexPath.row];
    NSParameterAssert(recording);
    NSDictionary *phrase = [[self.model.phrases filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id = %@",recording[@"phrase_id"]]] lastObject];
    NSParameterAssert(phrase);
    
    NSString *pt = phrase[@"phrase_text"];
    cell.recordingNameLabel.text = [NSString stringWithFormat:@"Rec_%@_%@", recording[@"id"] ,[pt stringByReplacingOccurrencesOfString:@" " withString:@"_"]];

    cell.delegate = self;
    
    return cell;
}


#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if(alertView.tag >= DELETE_ALERT && buttonIndex == 1)
    {
        __weak typeof(self) weakSelf = self;
        NSDictionary *recordingToDelete = self.model.recordings[alertView.tag-DELETE_ALERT];
        [MLProgressHUD showHUDAddedTo:self.view animated:YES];
        
        [self.model deleteRecording:recordingToDelete forUid:self.uid gid:self.gid completion:^(NSError *error) {
            
            [MLProgressHUD hideAllHUDsForView:weakSelf.view animated:YES];
            if(error)
                [[[VPAlertView alloc] initWithTitle:NSLocalizedString(@"Błąd łączności",@"") message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil] show];
            else
            {
                [weakSelf.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:alertView.tag - DELETE_ALERT inSection:0]] withRowAnimation:UITableViewRowAnimationRight];
                weakSelf.phraseProgressLabel.attributedText = self.progressString;
                self.recordingView.numberOfElements = [self.model.selectedPhrase[@"recordings_needed"] integerValue];
                self.recordingView.numberOfActiveElements = self.model.recordings.count;

            }
        }];
    }
}

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if(alertView.tag == NEXT_PHRASE_ALERT && buttonIndex == 1)
    {
       if(self.model.untrainedPhrases.count)
       {
           [self setSelectedPhrase:self.model.untrainedPhrases.lastObject];
       }
    }
}


#pragma mark - UITextFieldDelegate


- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    if(textField==self.phraseTextField) [self setSelectedPhrase: [self.pickerView selectedRowInComponent:0] == 0 ? nil:self.model.phrases[[self.pickerView selectedRowInComponent:0]-1]];
    
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    return ![VPAudioManager sharedInstance].isRecording && ![VPAudioManager sharedInstance].isPlaying;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && CGRectContainsPoint(self.recordingView.frame, [touch locationInView:self.view])) return NO;
    return YES;
    
}

#pragma mark - VPRecordingCellDelegate

- (void)recordingCellPlayButtonTapped:(VPRecordingCell *)cell
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    
    if([VPAudioManager sharedInstance].isPlaying)
    {
        [[VPAudioManager sharedInstance] stop];
    }
    if([VPAudioManager sharedInstance].isRecording)
    {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    
    [MLProgressHUD showHUDAddedTo:self.view animated:YES];
    [[MLImageCache sharedInstance] getDataAtURL:[NSURL URLWithString:self.model.recordings[indexPath.row][@"recording_path"]] withPriority:NSOperationQueuePriorityHigh completion:^(NSData *data, id referenceObject, BOOL loadedFromCache)
     {
         [MLProgressHUD hideAllHUDsForView:weakSelf.view animated:YES];
         
         if(![VPAudioManager sharedInstance].isPlaying) [[VPAudioManager sharedInstance] playFromFile:[[VPAudioManager sharedInstance] saveDataAsRecording:data]];
         [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
     } referenceObject:nil];
}

- (void)recordingCellDeleteButtonTapped:(VPRecordingCell *)cell
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Czy na pewno?",@"") message:NSLocalizedString(@"Kasowanie nagrania jest nieodwracalne",@"") delegate:self cancelButtonTitle:@"Nie" otherButtonTitles:@"Tak", nil];
    av.tag = DELETE_ALERT + indexPath.row;
    
    [av show];
}

@end
