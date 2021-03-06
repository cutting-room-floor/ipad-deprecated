//
//  DSMapView.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 3/8/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

#import "DSMapView.h"

#import "RMMarker.h"
#import "RMLayerCollection.h"

@interface DSMapView ()

@property (nonatomic, assign) BOOL touchesMoved;
@property (nonatomic, assign) CGPoint lastInteractivityPoint;

@end

#pragma mark -

@implementation DSMapView

@synthesize interactivityDelegate;
@synthesize topMostMapView;
@synthesize touchesMoved;
@synthesize lastInteractivityPoint;

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.touchesMoved = NO;
    
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.touchesMoved = YES;
    
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Hack to dismiss interactivity when tapping on interactive
    // map view, despite it being the only popover passthrough view.
    // Adding, say, the top toolbar to passthrough results in multiple
    // popovers possibly being displayed (ex: interactivity + layers),
    // which is grounds for App Store rejection. Easiest thing for now
    // is just to assume all map views (currently main & TileStream 
    // preview) have a top toolbar and account for that. 
    //
    // See https://github.com/developmentseed/MapBoxiPad/issues/52
    //
    if ([[[touches allObjects] objectAtIndex:0] locationInView:self].y <= 44)
    {
        [self.interactivityDelegate hideInteractivityAnimated:YES];

        return;
    }

    UITouch *touch = [[touches allObjects] objectAtIndex:0];

    // hit test for markers to skirt interactivity
    //
    NSObject *touched = [self.contents.overlay hitTest:[touch locationInView:self]];
    
    BOOL markerTap = ([touched isKindOfClass:[RMMarker class]] || ([touched isKindOfClass:[CALayer class]] && [[(CALayer *)touched superlayer] isKindOfClass:[RMMarker class]]));
    
    // one-finger single-tap for interactivity - but wait for possible double-tap
    //
    if (lastGesture.numTouches == 1 && touch.tapCount == 1 && self.interactivityDelegate && ! markerTap)
    {
        self.lastInteractivityPoint = lastGesture.center;
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                                 selector:@selector(triggerInteractivity:) 
                                                   object:nil];
        
        [self performSelector:@selector(triggerInteractivity:) 
                   withObject:nil 
                   afterDelay:0.25];
    }
    
    // one-finger double-tap to zoom - but cancel any single-tap interactivity
    //
    else if (lastGesture.numTouches == 1 && touch.tapCount == 2)
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                                 selector:@selector(triggerInteractivity:) 
                                                   object:nil];
        
        if (self.interactivityDelegate)
            [self.interactivityDelegate hideInteractivityAnimated:NO];
        
        
        [self zoomInToNextNativeZoomAt:lastGesture.center animated:YES];
    }

    // two-finger tap to zoom out
    //
    if (lastGesture.numTouches == 2 && ! self.touchesMoved)
    {
        if (self.contents.zoom - 1.0 < kLowerZoomBounds)
        {
            float factor = exp2f(kLowerZoomBounds - self.contents.zoom);
            
            [self zoomByFactor:factor near:lastGesture.center animated:YES];
        }

        else
            [self zoomOutToNextNativeZoomAt:lastGesture.center animated:YES];

        [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                                 selector:@selector(triggerInteractivity:) 
                                                   object:nil];
        
        if (self.interactivityDelegate)
            [self.interactivityDelegate hideInteractivityAnimated:NO];
    }
        
    else if (touch.tapCount != 2)
    {
        // avoid double-send of double-tap zoom
        //
        [super touchesEnded:touches withEvent:event];
    }
}

#pragma mark -

- (void)delayedResumeExpensiveOperations
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resumeExpensiveOperations) object:nil];
	[self performSelector:@selector(resumeExpensiveOperations) withObject:nil afterDelay:0.1];
}

- (void)triggerInteractivity:(NSValue *)pointValue
{
    [self.interactivityDelegate presentInteractivityAtPoint:self.lastInteractivityPoint];
}

#pragma mark -

- (DSMapView *)topMostMapView
{
    /**
     * This iterates our own peer views, bottom-up, returning the top-most
     * map one, which might just be us.
     */

    DSMapView *returnedMapView = self;
    
    for (UIView *peerView in [[self superview] subviews])
    {
        if ( ! [peerView isKindOfClass:[RMMapView class]])
            break;
        
        returnedMapView = (DSMapView *)peerView;
    }
    
    return returnedMapView;
}

- (void)insertLayerMapView:(DSMapBoxTiledLayerMapView *)layerMapView
{
    [[self superview] insertSubview:(UIView *)layerMapView aboveSubview:self.topMostMapView];
}

@end