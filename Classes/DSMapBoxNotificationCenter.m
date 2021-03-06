//
//  DSMapBoxNotificationCenter.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/2/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapBoxNotificationCenter.h"

#import <QuartzCore/QuartzCore.h>

@interface DSMapBoxNotificationView : UIView

@end

#pragma mark -

@implementation DSMapBoxNotificationView

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    [[UIColor colorWithWhite:0.0 alpha:0.6] set];
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
                                               byRoundingCorners:UIRectCornerBottomRight
                                                     cornerRadii:CGSizeMake(12, 12)];
    
    CGContextAddPath(context, [path CGPath]);
    
    CGContextFillPath(context);
}

@end

#pragma mark -

@interface DSMapBoxNotificationCenter ()

@property (nonatomic, strong) DSMapBoxNotificationView *view;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSMutableArray *queue;

- (id)initWithFrame:(CGRect)rect;

@end

#pragma mark -

@implementation DSMapBoxNotificationCenter

@synthesize view;
@synthesize label;
@synthesize queue;

+ (DSMapBoxNotificationCenter *)sharedInstance
{
    static dispatch_once_t token;
    static DSMapBoxNotificationCenter *sharedInstance = nil;
    
    dispatch_once(&token, ^{ sharedInstance = [[self alloc] initWithFrame:CGRectMake(0, 44, 500, 30)]; });  
    
    return sharedInstance;
}

#pragma mark -

- (id)initWithFrame:(CGRect)rect
{
    self = [super init];

    if (self != nil)
    {
        view = [[DSMapBoxNotificationView alloc] initWithFrame:rect];
        
        view.backgroundColor        = [UIColor clearColor];
        view.userInteractionEnabled = NO;

        view.layer.shadowOffset     = CGSizeMake(0, 1);
        view.layer.shadowOpacity    = 0.2;
        
        label = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, 480, 20)];
        
        label.textColor        = [UIColor whiteColor];
        label.backgroundColor  = [UIColor clearColor];
        label.shadowColor      = [UIColor blackColor];
        label.shadowOffset     = CGSizeMake(0, 1);
        label.font             = [UIFont systemFontOfSize:13.0];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        [view addSubview:label];
        
        [[((UIWindow *)[[[UIApplication sharedApplication] windows] objectAtIndex:0]).subviews objectAtIndex:0] addSubview:view];
        
        queue = [NSMutableArray array];
    }
    
    return self;
}

#pragma mark -

- (void)notifyWithMessage:(NSString *)message
{
    // append to queue, in case we're backed up
    //
    if (message)
        [self.queue addObject:message];
    
    // continue if we've got at least one message queued
    //
    if ([self.queue count])
    {
        // process oldest item in queue
        //
        self.label.text = [self.queue objectAtIndex:0];
        
        // dequeue
        //
        [self.queue removeObjectAtIndex:0];
        
        // resize as needed & start left of screen
        //
        CGSize labelSize   = self.label.frame.size;
        CGSize textSize    = [self.label.text sizeWithFont:self.label.font];
        
        CGFloat adjustment = labelSize.width - textSize.width;

        self.view.frame = CGRectMake(-self.view.frame.size.width - adjustment,  
                                      self.view.frame.origin.y, 
                                      self.view.frame.size.width - adjustment, 
                                      self.view.frame.size.height);
        
        // animate in & out
        //
        [UIView animateWithDuration:0.25
                              delay:0.0
                            options:UIViewAnimationCurveEaseOut
                         animations:^(void)
                         {
                             self.view.frame = CGRectMake(0, 
                                                          self.view.frame.origin.y, 
                                                          self.view.frame.size.width, 
                                                          self.view.frame.size.height);
                         }
                         completion:^(BOOL finished)
                         {
                             [UIView animateWithDuration:0.25
                                                   delay:3.0
                                                 options:UIViewAnimationCurveEaseIn
                                              animations:^(void)
                                              {
                                                  self.view.frame = CGRectMake(-self.view.frame.size.width, 
                                                                                self.view.frame.origin.y, 
                                                                                self.view.frame.size.width, 
                                                                                self.view.frame.size.height);
                                              }
                                              completion:^(BOOL finished)
                                              {
                                                  // loop to continue dequeueing
                                                  //
                                                  [self notifyWithMessage:nil];
                                              }];
                         }];
    }
}

@end