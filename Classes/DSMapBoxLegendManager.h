//
//  DSMapBoxLegendManager.h
//  MapBoxiPad
//
//  Created by Justin Miller on 11/9/11.
//  Copyright (c) 2011 Development Seed. All rights reserved.
//

#define kDSMapBoxLegendManagerHideShowDuration       0.25f
#define kDSMapBoxLegendManagerCollapseExpandDuration 0.25f
#define kDSMapBoxLegendManagerPostInteractionDelay   2.0f

@interface DSMapBoxLegendManager : NSObject <UIScrollViewDelegate, UIWebViewDelegate, UIAlertViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, retain) NSArray *legendSources;

- (id)initWithView:(UIView *)view;

@end