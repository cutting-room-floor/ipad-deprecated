//
//  DSMapBoxErrorView.h
//  MapBoxiPad
//
//  Created by Justin Miller on 7/13/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DSMapBoxErrorView : UIView
{
    UIImageView *imageView;
    UITextField *textField;
}

+ (id)errorViewWithMessage:(NSString *)inMessage;

- (id)initWithMessage:(NSString *)inMessage;

@property (nonatomic, assign) NSString *message;

@end