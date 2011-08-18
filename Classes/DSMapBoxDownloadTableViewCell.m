//
//  DSMapBoxDownloadTableViewCell.m
//  MapBoxiPad
//
//  Created by Justin Miller on 8/16/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapBoxDownloadTableViewCell.h"

#import "MapBoxConstants.h"

#import "SSPieProgressView.h"

#import <QuartzCore/QuartzCore.h>

@implementation DSMapBoxDownloadTableViewCell

@synthesize pie;
@synthesize primaryLabel;
@synthesize secondaryLabel;
@synthesize isPaused;

- (void)awakeFromNib
{
    self.backgroundColor          = [UIColor whiteColor];
    
    self.pie.pieFillColor         = [UIColor colorWithCGColor:CGColorCreateCopyWithAlpha([kMapBoxBlue CGColor], 0.5)];
    self.pie.pieBackgroundColor   = [UIColor clearColor];
    self.pie.pieBorderColor       = kMapBoxBlue;
 
    self.pie.pieBorderWidth       = 2.0;
    
    originalPrimaryLabelTextColor = [self.primaryLabel.textColor retain];
}

- (void)dealloc
{
    [originalPrimaryLabelTextColor release];
    [pie release];
    
    [super dealloc];
}

#pragma mark -

- (void)setIsPaused:(BOOL)flag
{
    if (flag == isPaused)
        return;
    
    isPaused = flag;
    
    if (flag)
    {
        // dim primary label
        //
        self.primaryLabel.textColor = self.secondaryLabel.textColor;
        
        // hide the animated pie
        //
        self.pie.hidden = YES;
        
        // draw a pulsing, empty, dimmed pie
        //
        CGSize pieSize = self.pie.bounds.size;
        
        UIGraphicsBeginImageContext(pieSize);
        
        CGContextRef c = UIGraphicsGetCurrentContext();
        
        [self.secondaryLabel.textColor setStroke];
        
        CGContextSetLineWidth(c, self.pie.pieBorderWidth);
        
        CGContextStrokeEllipseInRect(c, CGRectMake(self.pie.pieBorderWidth / 2, self.pie.pieBorderWidth / 2, pieSize.width - self.pie.pieBorderWidth, pieSize.height - self.pie.pieBorderWidth));
        
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        
        UIGraphicsEndImageContext();
        
        UIView *pulseView = [[[UIView alloc] initWithFrame:self.pie.frame] autorelease];
        
        pulseView.layer.contents = (id)[image CGImage];
        
        [self.pie.superview insertSubview:pulseView aboveSubview:self.pie];
        
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
        [UIView setAnimationRepeatAutoreverses:YES];
        [UIView setAnimationRepeatCount:MAXFLOAT];
        [UIView setAnimationDuration:1.0];
        
        pulseView.alpha = 0.2;
        
        [UIView commitAnimations];
    }
    else
    {
        // revert primary label
        //
        self.primaryLabel.textColor = originalPrimaryLabelTextColor;
        
        // remove pulsing view
        //
        [[self.pie.superview.subviews lastObject] removeFromSuperview];
        
        // fade in pie view
        //
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:1.0];
        
        self.pie.hidden = NO;
        
        [UIView commitAnimations];
    }
}

@end