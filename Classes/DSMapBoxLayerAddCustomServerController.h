//
//  DSMapBoxLayerAddCustomServerController.h
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/17/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "ASIHTTPRequestDelegate.h"

@interface DSMapBoxLayerAddCustomServerController : UIViewController <UITextFieldDelegate, 
                                                                      UITableViewDelegate, 
                                                                      UITableViewDataSource,
                                                                      ASIHTTPRequestDelegate>
{
    IBOutlet UITextField *entryField;
    IBOutlet UIActivityIndicatorView *spinner;
    IBOutlet UIImageView *successImage;
    IBOutlet UITableView *recentServersTableView;
    ASIHTTPRequest *validationRequest;
    NSURL *finalURL;
}

@property (nonatomic, retain) NSURL *finalURL;

- (IBAction)tappedNextButton:(id)sender;

@end